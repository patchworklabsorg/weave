# frozen_string_literal: true

# Passwords for users who have a Patchwork Active Directory account.
#
# AD holds the only copy of these passwords. Weave checks them with an LDAPS
# bind and writes new ones to AD. It never saves them. A user is linked to AD
# when an AD user under the base DN has employeeID equal to the user's p_id.
# Weave then records `users.directory_linked_at` and the AD objectGUID, and
# replaces the local password digest with a random one, so the old Weave
# password stops working.
#
# The p_id is public (it is the OIDC sub), so whoever can write employeeID in
# AD can point an AD account at any Weave user. Two rules limit that:
# - The link is pinned to the objectGUID. Another AD object that later gets
#   the same employeeID does not match, and password sign-in fails closed.
# - Admins (admin, superadmin, owner) are never linked automatically. An
#   operator links them with `bin/rails active_directory:link_user`.
#
# Users with no AD account keep Weave's own password flow. The feature is off
# until ActiveDirectory::Config is enabled and complete. See
# docs/ACTIVE_DIRECTORY.md.
#
# Attempts are counted per user. Each password check (a bind, or a change
# with the current password) reserves one attempt before Weave sends it, with
# an atomic increment, so parallel requests can't all slip through. Only a
# success clears the count. After MAX_FAILURES, Weave sends nothing more for
# that user until FAILURE_WINDOW has passed with no attempt sent to AD (a
# sliding window, like the AD lockout observation window). Rack::Attack adds limits per email
# and per IP on top.
module DirectoryPasswords
  MAX_FAILURES = 5
  FAILURE_WINDOW = 15.minutes

  # What a sign-in with a password can come to.
  #   :authenticated         AD accepted the password
  #   :not_directory         no linked AD account: use Weave's own password check
  #   :invalid               wrong password, or an AD account that can't sign in
  #   :locked                AD locked the account
  #   :throttled             too many attempts in Weave's own window
  #   :must_change_password  the password is right but expired or must change
  #   :unlinked              the user was linked, but the pinned AD account is gone
  #   :unavailable           AD did not answer or is not configured
  #
  # A disabled, expired or restricted AD account (533, 701, 530, 531) answers
  # :invalid. AD sends those codes only for the right password, so a separate
  # message would tell a guesser that the guess was right.
  SIGN_IN_STATUSES = %i[authenticated not_directory invalid locked throttled must_change_password unlinked unavailable].freeze

  # What a password write can come to: :ok, :not_directory, :policy_rejected,
  # :invalid_current_password, :throttled, :not_permitted, :unlinked,
  # :unavailable or :failed.

  # The AD object that answers for a linked user is not the one Weave pinned.
  class LinkMismatch < StandardError; end

  class << self
    attr_writer :client

    def client = @client || ActiveDirectory::Client.new

    delegate :config, to: :client

    # On means the operator turned it on (AD_ENABLED). Usable means the
    # configuration is also complete. On but not usable fails closed.
    delegate :enabled?, to: :config

    def linked?(user) = user.directory_linked_at.present?

    # Who may sign in with a password: admins, and users already linked to AD.
    # Reads Weave's database only, so a password from anyone else never
    # reaches AD and can't link an account.
    def password_sign_in?(user) = user.admin? || (enabled? && linked?(user))

    # Admins are linked only by an operator (see the module comment).
    def auto_linkable?(user) = !user.admin?

    # True when the user's password lives in AD. Raises
    # ActiveDirectory::Unavailable.
    def directory_user?(user)
      return false unless enabled?
      return true if linked?(user)

      !lookup(user).nil?
    end

    # The linked AD entry for the user, or nil when the user has no AD
    # account Weave may use. Links the user when it finds one and the user may
    # be linked automatically. Raises ActiveDirectory::Unavailable and
    # LinkMismatch.
    def lookup(user)
      ensure_usable!

      entry = client.find_employee(user.p_id)
      if linked?(user)
        check_pinned!(user, entry)
      elsif entry && auto_linkable?(user)
        link!(user, entry)
      elsif entry
        Rails.logger.info("[active_directory] #{user.p_id} has an AD account but is an admin: link with active_directory:link_user")
        return nil
      end
      entry
    rescue ActiveDirectory::AmbiguousLink => e
      Rails.logger.error("[active_directory] #{e.message}")
      raise ActiveDirectory::Unavailable, "ambiguous link"
    end

    # Links the user without a bind, for the background job after a sign-in
    # and for the rake task. Returns true when linked. explicit: true is the
    # operator step that may also link an admin.
    def link(user, explicit: false)
      return false unless enabled? && config.usable?
      return true if linked?(user)

      ensure_usable!
      entry = client.find_employee(user.p_id)
      return false if entry.nil?
      return false unless explicit || auto_linkable?(user)

      link!(user, entry)
      true
    rescue ActiveDirectory::Unavailable, ActiveDirectory::AmbiguousLink => e
      Rails.logger.warn("[active_directory] could not link #{user.p_id}: #{e.message}")
      false
    end

    def sign_in(user, password)
      return :not_directory unless enabled?
      return :invalid if password.blank?
      # Checked first so that a throttled user costs AD nothing. Refused
      # attempts reach no DC, so they do not move the window.
      return :throttled if throttled?(user)

      entry = lookup(user)
      return (linked?(user) ? :unlinked : :not_directory) if entry.nil?
      return :throttled unless reserve_attempt(user)

      status = sign_in_status(client.authenticate(entry, password))
      clear_attempts(user) if status == :authenticated
      status
    rescue LinkMismatch
      :unlinked
    rescue ActiveDirectory::Unavailable => e
      Rails.logger.error("[active_directory] sign-in for #{user.p_id} failed closed: #{e.message}")
      :unavailable
    end

    # Self-service change with the current password. Every result but :ok
    # counts as an attempt: a policy refusal (0000052D) also tells that the
    # current password was right.
    def change(user, current:, new:)
      return :not_directory unless enabled?

      write(user) do |entry|
        next :throttled unless reserve_attempt(user)

        status = client.change_password(entry, current: current, new: new)
        clear_attempts(user) if status == :ok
        status
      end
    end

    # A reset without the current password: an admin reset, or a member who
    # forgot it and just signed in another way.
    def reset(user, new)
      return :not_directory unless enabled?

      write(user) { |entry| client.reset_password(entry, new) }
    end

    def throttled?(user) = attempts(user) >= MAX_FAILURES

    # Every attempt store is shared by the app processes, except a
    # MemoryStore in production (Rack::Attack falls back to one when
    # REDIS_CACHE_URL is missing). There the per-user limit would multiply by
    # the number of processes, so Weave refuses to use AD.
    def attempt_store_shared?
      !(Rails.env.production? && store.is_a?(ActiveSupport::Cache::MemoryStore))
    end

    private

    def write(user)
      entry = lookup(user)
      return (linked?(user) ? :unlinked : :not_directory) if entry.nil?

      status = yield entry
      Rails.logger.info("[active_directory] password write for #{user.p_id}: #{status}")
      status
    rescue LinkMismatch
      :unlinked
    rescue ActiveDirectory::Unavailable => e
      Rails.logger.error("[active_directory] password write for #{user.p_id} failed closed: #{e.message}")
      :unavailable
    end

    def ensure_usable!
      unless config.usable?
        raise ActiveDirectory::Unavailable, "Active Directory is enabled but not configured: missing #{config.missing.join(', ')}"
      end
      raise ActiveDirectory::Unavailable, "the attempt store is not shared (set REDIS_CACHE_URL)" unless attempt_store_shared?
    end

    def check_pinned!(user, entry)
      if entry.nil?
        Rails.logger.error("[active_directory] #{user.p_id} is linked, but AD has no account with that employeeID")
        raise LinkMismatch
      end
      return if entry.object_guid.present? && entry.object_guid == user.directory_object_guid

      Rails.logger.error("[active_directory] #{user.p_id} is pinned to objectGUID #{user.directory_object_guid.inspect}, " \
                         "but #{entry.dn} (#{entry.object_guid.inspect}) has the employeeID now")
      raise LinkMismatch
    end

    def sign_in_status(bind_status)
      case bind_status
      when :ok then :authenticated
      when :locked then :locked
      when :must_change_password, :password_expired then :must_change_password
      else :invalid
      end
    end

    # From here on AD holds the password. The random digest makes the old
    # Weave password useless. update_columns: no validations, no callbacks,
    # no password complexity rules for a value nobody will ever type.
    def link!(user, entry)
      raise ActiveDirectory::Unavailable, "AD returned no objectGUID for #{entry.dn}" if entry.object_guid.blank?

      user.update_columns( # rubocop:disable Rails/SkipsModelValidations
        directory_linked_at: Time.current,
        directory_object_guid: entry.object_guid,
        password_digest: BCrypt::Password.create(SecureRandom.base58(48))
      )
      Rails.logger.info("[active_directory] linked #{user.p_id} to #{entry.dn}")
    end

    # The Rack::Attack store is shared by every app process (Redis in
    # production) and reset between specs.
    def store = Rack::Attack.cache.store

    def attempt_key(user) = "#{Rack::Attack.cache.prefix}:directory-attempts:#{user.id}"

    def active_key(user) = "#{attempt_key(user)}:active"

    def attempts(user)
      return 0 unless store.exist?(active_key(user))

      store.read(attempt_key(user), raw: true).to_i
    end

    # The count goes up with an atomic increment, so N parallel requests get
    # N different counts and at most MAX_FAILURES of them go through. A
    # second key marks the window as active and moves forward with each
    # attempt. When it has expired (FAILURE_WINDOW with no attempt), the count
    # starts again. So the window slides, like the AD lockout observation
    # window.
    def reserve_attempt(user)
      key = attempt_key(user)
      store.delete(key) unless store.exist?(active_key(user))
      store.write(active_key(user), 1, expires_in: FAILURE_WINDOW)
      store.increment(key, 1, expires_in: 1.day).to_i <= MAX_FAILURES
    end

    def clear_attempts(user)
      store.delete(attempt_key(user))
      store.delete(active_key(user))
    end

  end
end
