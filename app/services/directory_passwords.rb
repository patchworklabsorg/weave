# frozen_string_literal: true

# Passwords for users who have a Patchwork Active Directory account.
#
# AD holds the only copy of these passwords. Weave checks them with an LDAPS
# bind and writes new ones to AD. It never saves them. A user is linked to AD
# when an AD user under the base DN has employeeID equal to the user's p_id.
# Weave then records `users.directory_linked_at` and replaces the local
# password digest with a random one, so the old Weave password stops working.
#
# Users with no AD account keep Weave's own password flow. The feature is off
# until ActiveDirectory::Config is enabled and complete. See
# docs/ACTIVE_DIRECTORY.md.
#
# Failed attempts are counted per user. After MAX_FAILURES within
# FAILURE_WINDOW, Weave stops sending binds for that user until the window
# ends. This keeps Weave from being a password-guessing oracle against AD from
# many IPs, and keeps Weave below the AD lockout threshold. Rack::Attack adds
# limits per email and per IP on top.
module DirectoryPasswords
  MAX_FAILURES = 5
  FAILURE_WINDOW = 15.minutes

  # What a sign-in with a password can come to.
  #   :authenticated         AD accepted the password
  #   :not_directory         no AD account: use Weave's own password check
  #   :invalid               wrong password (or no such AD account)
  #   :locked                AD locked the account
  #   :throttled             too many failures in Weave's own window
  #   :disabled              AD account disabled, expired or restricted
  #   :must_change_password  the password is right but expired or must change
  #   :unlinked              the user was linked, but the AD account is gone
  #   :unavailable           AD did not answer or is not configured
  SIGN_IN_STATUSES = %i[authenticated not_directory invalid locked throttled disabled must_change_password unlinked unavailable].freeze

  # What a password write can come to: :ok, :not_directory, :policy_rejected,
  # :invalid_current_password, :throttled, :not_permitted, :unlinked,
  # :unavailable or :failed.

  class << self
    attr_writer :client

    def client = @client || ActiveDirectory::Client.new

    delegate :config, to: :client

    # On means the operator turned it on (AD_ENABLED). Usable means the
    # configuration is also complete. On but not usable fails closed.
    delegate :enabled?, to: :config

    def linked?(user) = user.directory_linked_at.present?

    # True when the user's password lives in AD. Looks the user up when Weave
    # has not linked them yet. Raises ActiveDirectory::Unavailable.
    def directory_user?(user)
      return false unless enabled?
      return true if linked?(user)

      !lookup(user).nil?
    end

    # Finds the AD account and links the user when it exists. Returns the
    # entry or nil. Raises ActiveDirectory::Unavailable.
    def lookup(user)
      unavailable! unless config.usable?

      entry = client.find_employee(user.p_id)
      link!(user) if entry && !linked?(user)
      entry
    rescue ActiveDirectory::AmbiguousLink => e
      Rails.logger.error("[active_directory] #{e.message}")
      raise ActiveDirectory::Unavailable, "ambiguous link"
    end

    # Links the user without a bind, for the background job after a sign-in
    # and for the rake task. Returns true when linked.
    def link(user)
      return false unless enabled? && config.usable?
      return true if linked?(user)

      !lookup(user).nil?
    rescue ActiveDirectory::Unavailable => e
      Rails.logger.warn("[active_directory] could not link #{user.p_id}: #{e.message}")
      false
    end

    def sign_in(user, password)
      return :not_directory unless enabled?
      return :invalid if password.blank?
      return :throttled if throttled?(user)

      entry = lookup(user)
      return (linked?(user) ? :unlinked : :not_directory) if entry.nil?

      status = sign_in_status(client.authenticate(entry, password))
      record_failure(user) if %i[invalid locked].include?(status)
      clear_failures(user) if status == :authenticated
      status
    rescue ActiveDirectory::Unavailable => e
      Rails.logger.error("[active_directory] sign-in for #{user.p_id} failed closed: #{e.message}")
      :unavailable
    end

    # Self-service change with the current password.
    def change(user, current:, new:)
      return :not_directory unless enabled?
      return :throttled if throttled?(user)

      write(user) do |entry|
        status = client.change_password(entry, current: current, new: new)
        record_failure(user) if status == :invalid_current_password
        status
      end
    end

    # A reset without the current password: an admin reset, or a member who
    # forgot it and just signed in another way.
    def reset(user, new)
      write(user) { |entry| client.reset_password(entry, new) }
    end

    def throttled?(user) = failures(user) >= MAX_FAILURES

    private

    def write(user)
      return :not_directory unless enabled?

      entry = lookup(user)
      return (linked?(user) ? :unlinked : :not_directory) if entry.nil?

      status = yield entry
      Rails.logger.info("[active_directory] password write for #{user.p_id}: #{status}")
      status
    rescue ActiveDirectory::Unavailable => e
      Rails.logger.error("[active_directory] password write for #{user.p_id} failed closed: #{e.message}")
      :unavailable
    end

    def sign_in_status(bind_status)
      case bind_status
      when :ok then :authenticated
      when :locked then :locked
      when :disabled, :account_expired, :restricted then :disabled
      when :must_change_password, :password_expired then :must_change_password
      else :invalid
      end
    end

    # From here on AD holds the password. The random digest makes the old
    # Weave password useless. update_columns: no validations, no callbacks,
    # no password complexity rules for a value nobody will ever type.
    def link!(user)
      user.update_columns( # rubocop:disable Rails/SkipsModelValidations
        directory_linked_at: Time.current,
        password_digest: BCrypt::Password.create(SecureRandom.base58(48))
      )
      Rails.logger.info("[active_directory] linked #{user.p_id}")
    end

    def unavailable! = raise(ActiveDirectory::Unavailable, "Active Directory is enabled but not configured: missing #{config.missing.join(', ')}")

    # The Rack::Attack store is shared by every app process (Redis in
    # production) and reset between specs.
    def store = Rack::Attack.cache.store

    def failure_key(user) = "#{Rack::Attack.cache.prefix}:directory-failures:#{user.id}"

    def failures(user) = store.read(failure_key(user), raw: true).to_i

    def record_failure(user)
      store.increment(failure_key(user), 1, expires_in: FAILURE_WINDOW)
    end

    def clear_failures(user) = store.delete(failure_key(user))

  end
end
