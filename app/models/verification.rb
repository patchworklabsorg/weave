# frozen_string_literal: true

# One attempt at identity verification (layer 1 of the KYC proposal, see
# docs/KYC.md and VerificationFlow).
#
#   submitted -> pre_review -> awaiting_call -> call_scheduled -> verified | failed
#                     |
#                     +-> needs_resubmission (a document problem, with a note)
#
# "Document OK" ends pre-review (awaiting_call). The verifier then agrees a
# call time with the member by email or Slack, and records it as a separate
# step (call_scheduled).
#
# Each attempt links to the attempt before it (previous_attempt), so the
# history of a member reads as one chain.
#
# A pass has no time limit. Only a trigger (a birthday change, a legal name
# change or a blacklist review) ends it: the attempt stays verified, but
# reverification_required_at marks it as no longer standing, and the member
# needs a new call. The live call is never recorded:
# the record is the written attestation of the verifier and the append-only
# VerificationEvent rows.
#
# The ID image is encrypted with Lockbox. Only the pre-reviewer can see it
# during pre-review. After that, only a break-glass request can decrypt it
# (see BreakGlass). PurgeVerificationDocumentsJob deletes it a configured
# number of days after the attempt closes.
#
# Identifiers on the ID (document number, legal name, birth date) are never
# stored here. The verifier types them at the decision, and Weave gives them to
# the subscribers of VerificationIdentifiers::EVENT only.
# == Schema Information
#
# Table name: verifications
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  account_deleted_at        :datetime
#  age_consistent            :boolean
#  call_scheduled_for        :datetime
#  decided_at                :datetime
#  decision_reason           :text
#  document_purged_at        :datetime
#  document_type             :string
#  escalated_at              :datetime
#  escalation_note           :text
#  escalation_resolution     :string
#  escalation_resolved_at    :datetime
#  guardian_attended         :boolean          default(FALSE), not null
#  knot_review_reason        :string
#  pre_review_started_at     :datetime
#  pre_reviewed_at           :datetime
#  region_consistent         :boolean
#  resubmission_note         :text
#  reverification_reason     :string
#  reverification_required_at :datetime
#  status                    :string           default("submitted"), not null
#  verification_method       :string           default("document_call"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  call_scheduled_by_id      :bigint
#  escalation_resolved_by_id :bigint
#  guardian_consent_id       :bigint
#  knot_id                   :bigint
#  pre_reviewer_id           :bigint
#  previous_attempt_id       :bigint
#  second_verifier_id        :bigint
#  user_id                   :bigint
#  verifier_id               :bigint
#
# Indexes
#
#  index_verifications_on_account_deleted_at         (account_deleted_at)
#  index_verifications_on_call_scheduled_by_id       (call_scheduled_by_id)
#  index_verifications_on_escalation_resolved_by_id  (escalation_resolved_by_id)
#  index_verifications_on_guardian_consent_id        (guardian_consent_id)
#  index_verifications_on_knot_id                    (knot_id)
#  index_verifications_on_pre_reviewer_id            (pre_reviewer_id)
#  index_verifications_on_previous_attempt_id        (previous_attempt_id)
#  index_verifications_on_second_verifier_id         (second_verifier_id)
#  index_verifications_on_status                     (status)
#  index_verifications_on_user_id                    (user_id)
#  index_verifications_on_verifier_id                (verifier_id)
#
# Foreign Keys
#
#  fk_rails_...  (call_scheduled_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (escalation_resolved_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (guardian_consent_id => guardian_consents.id) ON DELETE => nullify
#  fk_rails_...  (knot_id => knots.id) ON DELETE => nullify
#  fk_rails_...  (pre_reviewer_id => users.id) ON DELETE => nullify
#  fk_rails_...  (previous_attempt_id => verifications.id) ON DELETE => nullify
#  fk_rails_...  (second_verifier_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verifier_id => users.id) ON DELETE => nullify
#
class Verification < ApplicationRecord
  include AASM
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :verif

  METHODS = %w[document_call digital_id_call].freeze
  DOCUMENT_TYPES = %w[passport national_id_card driving_licence residence_permit other].freeze
  # What Weave stores: IdDocumentConverter turns every accepted upload (JPEG,
  # PNG, HEIC/HEIF, PDF) into one of these at upload.
  CONTENT_TYPES = IdDocumentConverter::STORED_TYPES
  OPEN_STATES = %w[submitted pre_review awaiting_call call_scheduled].freeze
  ESCALATION_RESOLUTIONS = %w[retry_allowed ineligible].freeze
  # The only reasons a pass stops standing. A pass has no time limit.
  REVERIFICATION_REASONS = %w[birthday_changed legal_name_changed blacklist_review].freeze

  # These columns are the decision. They can't change after it.
  DECISION_COLUMNS = %w[verifier_id second_verifier_id guardian_attended guardian_consent_id age_consistent
                        region_consistent decision_reason decided_at].freeze

  has_paper_trail

  belongs_to :user, optional: true
  belongs_to :previous_attempt, class_name: "Verification", optional: true
  has_one :next_attempt, class_name: "Verification", foreign_key: :previous_attempt_id,
                         inverse_of: :previous_attempt, dependent: nil
  belongs_to :pre_reviewer, class_name: "User", optional: true
  belongs_to :call_scheduled_by, class_name: "User", optional: true
  belongs_to :verifier, class_name: "User", optional: true
  belongs_to :second_verifier, class_name: "User", optional: true
  belongs_to :guardian_consent, optional: true
  belongs_to :escalation_resolved_by, class_name: "User", optional: true
  # The Knot of the member, set at a pass for the whole chain of attempts (see
  # KnotLinker). It stays after the account is deleted, so a returning
  # member's history reads as one chain.
  belongs_to :knot, optional: true
  has_many :events, -> { order(:created_at, :id) }, class_name: "VerificationEvent",
                                                     dependent: :restrict_with_exception, inverse_of: :verification
  has_many :break_glass_records, dependent: :restrict_with_exception

  # The ID image waits for pre-review under Lockbox (the server key), so the
  # pre-reviewer can open it. When pre-review ends, IdDocumentVault seals it
  # to the master public key (SealedIdDocument) and destroys this copy.
  has_one_attached :id_document
  encrypts_attached :id_document
  has_one :sealed_document, class_name: "SealedIdDocument", dependent: :restrict_with_exception, inverse_of: :verification

  validates :verification_method, inclusion: { in: METHODS }
  validates :document_type, inclusion: { in: DOCUMENT_TYPES }, if: :document_call?
  validates :id_document, attached: true, if: -> { document_call? && new_record? }
  validates :id_document, content_type: CONTENT_TYPES,
                          size: { less_than_or_equal_to: VerificationSettings.max_image_size }
  validates :resubmission_note, presence: true, if: :needs_resubmission?
  validates :decision_reason, presence: true, if: -> { verified? || failed? }
  validates :escalation_resolution, inclusion: { in: ESCALATION_RESOLUTIONS }, allow_nil: true
  validates :reverification_reason, inclusion: { in: REVERIFICATION_REASONS }, allow_nil: true
  validates :reverification_reason, presence: true, if: :reverification_required_at?
  validates :knot_review_reason, inclusion: { in: KnotLinker::REVIEW_REASONS }, allow_nil: true
  validate :decision_unchanged, on: :update

  aasm column: :status, whiny_persistence: true do
    state :submitted, initial: true
    state :pre_review
    state :needs_resubmission
    state :awaiting_call
    state :call_scheduled
    state :verified
    state :failed

    event :start_pre_review do
      transitions from: :submitted, to: :pre_review
    end

    event :reject_document do
      transitions from: :pre_review, to: :needs_resubmission
    end

    # "Document OK": pre-review ends, and the attempt waits for a call time.
    event :approve_document do
      transitions from: :pre_review, to: :awaiting_call
    end

    event :schedule_call do
      transitions from: %i[awaiting_call call_scheduled], to: :call_scheduled
    end

    event :mark_verified do
      transitions from: :call_scheduled, to: :verified
    end

    event :mark_failed do
      transitions from: :call_scheduled, to: :failed
    end
  end

  scope :in_progress, -> { where(status: OPEN_STATES) }
  scope :escalation_open, -> { failed.where.not(escalated_at: nil).where(escalation_resolved_at: nil) }
  scope :knot_review_open, -> { call_scheduled.where.not(knot_review_reason: nil) }
  # The fraud-evidence hold: attempts linked to a blacklisted Knot are exempt
  # from the retention window while the flag stands (see docs/KYC.md).
  scope :under_fraud_hold, -> { joins(:knot).where(knots: { blacklisted: true }) }

  def fraud_hold? = knot&.blacklisted || false

  def document_call? = verification_method == "document_call"

  def digital_id_call? = verification_method == "digital_id_call"

  def in_progress? = OPEN_STATES.include?(status)

  def decided? = verified? || failed?

  # When the attempt ended: the decision, or the document rejection.
  def closed_at = decided_at || (pre_reviewed_at if needs_resubmission?)

  def escalation_open? = escalated_at.present? && escalation_resolved_at.nil?

  def ineligible? = escalation_resolution == "ineligible"

  # A trigger marked this pass as no longer standing: the member needs a new
  # call (see VerificationFlow.require_reverification).
  def reverification_required? = verified? && reverification_required_at.present?

  # A pass that still stands. There is no time limit: only a trigger ends it.
  def standing_pass? = verified? && reverification_required_at.nil?

  # A failed member can submit again after the cooldown, unless the attempt
  # went to the identity team lead.
  def retry_available_at
    return unless failed?

    decided_at + VerificationSettings.failed_call_cooldown
  end

  def document_stored? = (id_document.attached? || document_sealed?) && document_purged_at.nil?

  # Sealed to the master public key: only break-glass opens it.
  def document_sealed? = sealed_document.present? && document_purged_at.nil?

  # The people who made this decision, when it was a fail.
  def failing_verifier_ids = failed? ? [verifier_id, second_verifier_id].compact : []

  # Every attempt from this one back to the first, newest first.
  def chain
    attempts = []
    attempt = self
    while attempt && attempts.exclude?(attempt)
      attempts << attempt
      attempt = attempt.previous_attempt
    end
    attempts
  end

  private

  def decision_unchanged
    return if decided_at_was.nil?

    changed = DECISION_COLUMNS & changed_attributes.keys
    errors.add(:base, "The decision can't change after it is recorded") if changed.any?
  end

end
