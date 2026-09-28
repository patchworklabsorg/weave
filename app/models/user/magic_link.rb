# frozen_string_literal: true

# == Schema Information
#
# Table name: user_magic_links
# Database name: primary
#
#  id           :bigint           not null, primary key
#  expires_at   :datetime         not null
#  requested_ip :string
#  token_digest :string           not null
#  used_at      :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_magic_links_on_expires_at    (expires_at)
#  index_user_magic_links_on_token_digest  (token_digest) UNIQUE
#  index_user_magic_links_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class User
  # A single-use sign-in link.
  #
  # Each issued link is its own row rather than a set of columns on users, so
  # requesting a second link no longer invalidates the first. Users routinely
  # submit the login form twice — or hit "resend" because the first mail was
  # slow — and under the old single-column scheme whichever email they happened
  # to open first was already dead.
  #
  # Only a SHA-256 digest of the token is stored. The raw token exists in the
  # email and, briefly, in the mailer job's arguments; it is never at rest here.
  class MagicLink < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    set_public_id_prefix :mlink

    self.table_name = "user_magic_links"

    EXPIRATION = 15.minutes
    TOKEN_BYTES = 32

    belongs_to :user

    scope :unused, -> { where(used_at: nil) }
    scope :unexpired, -> { where(expires_at: Time.current..) }
    scope :live, -> { unused.unexpired }

    # Populated only on the instance returned by .issue!, so the mailer can send
    # what the digest can't reproduce.
    attr_accessor :token

    class << self
      def digest_for(token)
        OpenSSL::Digest::SHA256.hexdigest(token)
      end

      def issue!(user, requested_ip: nil)
        raw = SecureRandom.urlsafe_base64(TOKEN_BYTES)

        link = create!(
          user: user,
          token_digest: digest_for(raw),
          expires_at: EXPIRATION.from_now,
          requested_ip: requested_ip
        )
        link.token = raw
        link
      end

      # Digest lookup is a plain index hit on a value the caller can't influence
      # without already knowing the token, so there's no comparison to time.
      def for_token(token)
        return nil if token.blank?

        find_by(token_digest: digest_for(token))
      end

    end

    def used? = used_at.present?

    def expired? = expires_at <= Time.current

    def live? = !used? && !expired?

    # Atomic claim: the UPDATE only matches while the row is still live, so two
    # concurrent requests for the same link can't both win. That matters because
    # the common case for a double hit is a mail scanner racing the human.
    #
    # update_all rather than a model write precisely because it compiles to that
    # one conditional statement — a load-then-save would reintroduce the gap.
    #
    # Returns true if this request is the one that claimed the link.
    def consume!
      # rubocop:disable Rails/SkipsModelValidations
      claimed = self.class.live.where(id: id).update_all(used_at: Time.current, updated_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
      return false if claimed.zero?

      reload
      true
    end

    # Why a link can't be used, for messaging. nil when it's good.
    def rejection_reason
      return :used if used?
      return :expired if expired?
      # A locked, suspended or deactivated account can't sign in. Refusing the
      # link here, before it is consumed, stops a session row being created
      # that the next request would only throw away.
      return :inactive unless user.can_authenticate?

      nil
    end

  end

end
