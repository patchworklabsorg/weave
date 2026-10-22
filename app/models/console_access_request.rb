# frozen_string_literal: true

# == Schema Information
#
# Table name: console_access_requests
# Database name: primary
#
#  id           :bigint           not null, primary key
#  claimed_at   :datetime
#  code_digest  :string           not null
#  confirmed_at :datetime
#  confirmed_ip :string
#  expires_at   :datetime         not null
#  host         :string
#  kind         :string           not null
#  status       :string           default("pending"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint
#
# Indexes
#
#  index_console_access_requests_on_code_digest  (code_digest) UNIQUE
#  index_console_access_requests_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#

# A production console that waits to learn who uses it: `bin/rails console`
# (kind "console") or `bin/rails dbconsole` (kind "sql"). The console shows a
# code. The person who started it signs in to Weave as themselves and enters
# the code. The console then records its Console1984 session under that
# person's name and PWL id. See docs/CONSOLE_ACCESS.md.
#
# The class inherits from Console1984::Base so that Console1984 protects this
# table like its own: a console session cannot change whose session it is.
class ConsoleAccessRequest < Console1984::Base
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :cnslw

  self.table_name = "console_access_requests"

  KINDS = %w[console sql].freeze
  STATUSES = %w[pending confirmed rejected].freeze
  EXPIRATION = 10.minutes
  # Crockford base32: no I, L, O or U, so a person can read and type the code.
  CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  CODE_LENGTH = 8

  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  # Set only on the instance that .open! returns. Only the digest is stored.
  attr_accessor :code

  class << self
    def open!(kind:, host: nil)
      raw = Array.new(CODE_LENGTH) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)] }.join
      request = create!(kind:, host:, code_digest: digest_for(raw), expires_at: EXPIRATION.from_now)
      request.code = raw.scan(/.{4}/).join("-")
      request
    end

    # A pending, unexpired request, or nil.
    def find_pending_by_code(code)
      normalized = normalize(code)
      return if normalized.length != CODE_LENGTH

      where(status: "pending", expires_at: Time.current..).find_by(code_digest: digest_for(normalized))
    end

    def digest_for(code) = OpenSSL::Digest::SHA256.hexdigest(normalize(code))

    # Ignores case and dashes, and reads I and L as 1 and O as 0 (Crockford).
    def normalize(code) = code.to_s.upcase.gsub(/[^0-9A-Z]/, "").tr("ILO", "110")

  end

  def pending? = status == "pending"
  def confirmed? = status == "confirmed"
  def rejected? = status == "rejected"
  def expired? = pending? && expires_at.past?

  # The signed-in admin says "this console is mine". Only an admin can, and
  # only for a pending request that has not expired. Returns false otherwise.
  def confirm!(by:, ip: nil)
    return false unless by&.admin?

    record!("confirmed", by, ip)
  end

  # The signed-in admin says "this console is not mine". It stops.
  def reject!(by:, ip: nil) = record!("rejected", by, ip)

  # The console calls this when it sees the confirmation. It returns the user
  # once, so one confirmation opens one console. A confirmation that no
  # console claims within EXPIRATION stays unused. The user must still be an
  # admin, also when the row was written into the database by hand.
  def claim!
    return unless user&.admin?

    # One conditional UPDATE, so two consoles cannot claim the same confirmation.
    claimed = self.class.where(id:, status: "confirmed", claimed_at: nil, confirmed_at: EXPIRATION.ago..)
                  .update_all(claimed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    claimed == 1 ? user : nil
  end

  private

  def record!(new_status, by, ip)
    with_lock do
      return false unless pending? && !expired?

      update!(status: new_status, user: by, confirmed_at: Time.current, confirmed_ip: ip)
    end
  end

end
