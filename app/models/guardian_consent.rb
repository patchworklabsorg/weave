# frozen_string_literal: true

# A parent or guardian's consent for a member under 18 (see User#minor?).
#
# The member gives the guardian's name and email. Weave emails the guardian a
# link, and the guardian reads what Patchwork Labs is and consents on that page
# (see GuardianConsentsController). The same link later lets the guardian take
# the consent back. An admin can also record consent given on paper.
#
# Each request is its own row, so the history is kept. A new request
# supersedes the open one. Only a SHA-256 digest of the link token is stored,
# as with User::MagicLink.
# == Schema Information
#
# Table name: guardian_consents
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  expires_at                :datetime
#  flags                     :jsonb            not null
#  granted_at                :datetime
#  granted_fingerprint       :string
#  granted_ip                :string
#  granted_user_agent        :string
#  guardian_email_ciphertext :text
#  guardian_name_ciphertext  :text
#  note                      :text
#  review_note               :text
#  reviewed_at               :datetime
#  revoked_at                :datetime
#  sent_at                   :datetime
#  signed_name_ciphertext    :text
#  status                    :string           default("pending"), not null
#  text_version              :string
#  token_digest              :string
#  verification_note         :text
#  verified_at               :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  recorded_by_id            :bigint
#  reviewed_by_id            :bigint
#  revoked_by_id             :bigint
#  user_id                   :bigint           not null
#  verified_by_id            :bigint
#
# Indexes
#
#  index_guardian_consents_on_recorded_by_id  (recorded_by_id)
#  index_guardian_consents_on_reviewed_by_id  (reviewed_by_id)
#  index_guardian_consents_on_revoked_by_id   (revoked_by_id)
#  index_guardian_consents_on_token_digest    (token_digest) UNIQUE
#  index_guardian_consents_on_user_id         (user_id)
#  index_guardian_consents_on_verified_by_id  (verified_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (recorded_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (reviewed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (revoked_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (verified_by_id => users.id) ON DELETE => nullify
#
class GuardianConsent < ApplicationRecord
  include AASM
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :gcon

  # Change this when the consent text in config/locales/guardian_consent.en.yml
  # changes, so each grant records the text the guardian saw.
  TEXT_VERSION = "2026-10-12"

  # How long the guardian can use the link to consent. Revoking works for as
  # long as the consent stands.
  LINK_LIFETIME = 7.days
  RESEND_COOLDOWN = 10.minutes
  TOKEN_BYTES = 32

  has_paper_trail
  has_encrypted :guardian_name, :guardian_email, :signed_name

  belongs_to :user
  belongs_to :revoked_by, class_name: "User", optional: true
  belongs_to :recorded_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :verified_by, class_name: "User", optional: true

  # Populated only on the instance returned by .issue! and #reissue!, so the
  # mailer can send what the digest can't reproduce.
  attr_accessor :token

  before_validation :normalize_guardian_fields

  validates :guardian_name, presence: true, length: { maximum: 100 }
  validates :guardian_email, presence: true
  validates_email_format_of :guardian_email, allow_blank: true
  validates :signed_name, presence: true, length: { maximum: 100 }, if: :granted?
  # Offline consent has no link or signature in Weave, so the admin says where
  # the record of it is.
  validates :note, presence: true, if: :offline?
  validate :guardian_email_not_a_weave_account, on: :create

  aasm column: :status do
    state :pending, initial: true
    state :granted
    state :revoked
    state :superseded

    event :grant do
      transitions from: :pending, to: :granted
    end

    event :revoke do
      transitions from: :granted, to: :revoked
    end

    event :supersede do
      transitions from: :pending, to: :superseded
    end
  end

  # Pending or granted: the request that stands.
  scope :live, -> { where(status: %w[pending granted]) }

  # Granted consents with a flag that no admin has checked yet (see
  # GuardianConsentSignals).
  scope :needs_review, -> { granted.where(reviewed_at: nil).where("jsonb_array_length(flags) > 0") }

  class << self
    def digest_for(token) = OpenSSL::Digest::SHA256.hexdigest(token)

    def for_token(token)
      return nil if token.blank?

      find_by(token_digest: digest_for(token))
    end

    # Starts a request for the user's guardian. Supersedes the pending one.
    # Returns the new record: check #persisted? and #errors.
    def issue!(user, guardian_name:, guardian_email:)
      consent = new(user:, guardian_name:, guardian_email:)
      transaction do
        user.guardian_consents.pending.find_each(&:supersede!)
        consent.assign_token
        consent.save || raise(ActiveRecord::Rollback)
      end
      consent
    end

    # Consent the guardian gave outside Weave, for example on a paper form.
    def record_offline!(user, guardian_name:, guardian_email:, recorded_by:, note:)
      consent = new(user:, guardian_name:, guardian_email:, signed_name: guardian_name, recorded_by:, note:,
                    status: "granted", granted_at: Time.current, text_version: TEXT_VERSION)
      transaction do
        user.guardian_consents.live.find_each { |live| live.pending? ? live.supersede! : live.record_revoke!(by: recorded_by) }
        consent.save || raise(ActiveRecord::Rollback)
      end
      consent
    end

  end

  # A new link for the same guardian. The old link stops working.
  def reissue!
    assign_token
    save!
    self
  end

  def assign_token
    self.token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    self.token_digest = self.class.digest_for(token)
    self.sent_at = Time.current
    self.expires_at = LINK_LIFETIME.from_now
  end

  def link_expired? = expires_at.present? && expires_at <= Time.current

  def resend_allowed? = sent_at.nil? || sent_at.before?(RESEND_COOLDOWN.ago)

  def offline? = recorded_by_id.present?

  def needs_review? = granted? && reviewed_at.nil? && flags.any?

  # Only the spot check: nothing looked wrong.
  def suspicious? = (flags - ["spot_check"]).any?

  # A stronger check than the email link: an admin has a signed guardian form
  # and spoke with the guardian. Apps that hand out money or other risk ask
  # for it (the `guardian_verified` directory field). It belongs to this
  # consent, so a revoke or a new guardian ends it.
  def verified? = granted? && verified_at.present?

  # Verifying covers the review too.
  def record_verification!(by:, note:)
    update!(verified_at: Time.current, verified_by: by, verification_note: note,
            reviewed_at: reviewed_at || Time.current, reviewed_by: reviewed_by || by, review_note: review_note || note)
  end

  # An admin contacted the guardian and confirmed the consent.
  def record_review!(by:, note:)
    update!(reviewed_at: Time.current, reviewed_by: by, review_note: note)
  end

  # The row lock stops a double submit, or a grant racing a revoke, from
  # writing twice. Returns false when the consent was no longer pending.
  def record_grant!(signed_name:, ip:, user_agent:, fingerprint: nil)
    with_lock do
      return false unless pending?

      self.signed_name = signed_name
      self.granted_fingerprint = fingerprint.to_s.first(255).presence
      self.granted_at = Time.current
      self.granted_ip = ip
      self.granted_user_agent = user_agent.to_s.truncate(255)
      self.text_version = TEXT_VERSION
      grant!
    end
  end

  # by is the admin who revoked it, or nil when the guardian did. Returns false
  # when the consent was not granted.
  def record_revoke!(by: nil)
    with_lock do
      return false unless granted?

      self.revoked_at = Time.current
      self.revoked_by = by
      revoke!
    end
  end

  private

  def normalize_guardian_fields
    self.guardian_name = guardian_name.to_s.strip.presence
    self.guardian_email = guardian_email.to_s.strip.downcase.presence
    self.signed_name = signed_name.to_s.strip.presence
  end

  # The guardian must be someone else. A member's own second address, or
  # another member, can't consent for them.
  def guardian_email_not_a_weave_account
    return if guardian_email.blank?
    return unless User.exists?(email: guardian_email) || EmailAddress.exists?(email: guardian_email)

    errors.add(:guardian_email, "belongs to a Weave account. Use your parent or guardian's own email address.")
  end

end
