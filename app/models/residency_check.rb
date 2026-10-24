# frozen_string_literal: true

# One US residency check of a member (see ResidencyFlow and docs/KYC.md).
# OSPool lets only US residents use its capacity, and every verified member
# gets a result. Weave never asks about citizenship.
#
# Two sources:
#
# - identity_call: the verifier records the result at the decision of the
#   identity call. A US driver's license, learner's permit or state ID with a
#   current US address is enough (evidence "id_document"). A member without
#   one uploads a proof document with the ID.
# - document_review: a member who already passed identity verification
#   uploads a proof document, and a verifier decides it in pre-review. There
#   is no call.
#
#   submitted -> pre_review -> decided
#                    |
#                    +-> needs_resubmission (a document problem, with a note)
#
# Weave keeps only the result, the US state, the evidence type and the dates.
# The proof document follows the ID image rules: Lockbox during pre-review,
# then sealed to the master public key (ResidencyDocumentVault), and purged
# on the same schedule (PurgeVerificationDocumentsJob).
#
# A yes result stands for VerificationSettings.residency_valid_for, or until
# the state or country of the member's shipping address changes (ended_at).
# A no result stands until the member asks for a new check.
# == Schema Information
#
# Table name: residency_checks
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  account_deleted_at    :datetime
#  decided_at            :datetime
#  document_purged_at    :datetime
#  end_reason            :string
#  ended_at              :datetime
#  evidence_type         :string           not null
#  pre_review_started_at :datetime
#  pre_reviewed_at       :datetime
#  renewal_reminded_at   :datetime
#  resubmission_note     :text
#  source                :string           not null
#  status                :string           default("submitted"), not null
#  us_resident           :boolean
#  us_state              :string(2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  decided_by_id         :bigint
#  pre_reviewer_id       :bigint
#  user_id               :bigint
#  verification_id       :bigint
#
# Indexes
#
#  index_residency_checks_on_decided_at       (decided_at)
#  index_residency_checks_on_decided_by_id    (decided_by_id)
#  index_residency_checks_on_pre_reviewer_id  (pre_reviewer_id)
#  index_residency_checks_on_status           (status)
#  index_residency_checks_on_user_id          (user_id)
#  index_residency_checks_on_verification_id  (verification_id)
#
# Foreign Keys
#
#  fk_rails_...  (decided_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (pre_reviewer_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verification_id => verifications.id) ON DELETE => nullify
#
class ResidencyCheck < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :usres

  SOURCES = %w[identity_call document_review].freeze
  STATUSES = %w[submitted pre_review needs_resubmission decided].freeze
  OPEN_STATUSES = %w[submitted pre_review].freeze
  # The evidence that can show US residency. A US passport alone is not on
  # the list: it does not show where the member lives.
  EVIDENCE_TYPES = {
    "id_document"                      => "The member's US driver's license, learner's permit or state ID, with a current US address",
    "school_enrollment"                => "A current US school enrollment record",
    "guardian_state_id"                => "The guardian's US driver's license or state ID, with a current US address",
    "guardian_id_and_proof_of_address" => "The guardian's ID and a proof of a current US address",
    "none"                             => "No accepted evidence of US residency"
  }.freeze
  # The member's statement that they do not live in the US. It needs no
  # document and gives a no result.
  MEMBER_STATEMENT = "member_statement"
  # Evidence that comes as a separate upload (the ID itself is on the
  # identity attempt).
  UPLOAD_EVIDENCE = %w[school_enrollment guardian_state_id guardian_id_and_proof_of_address].freeze
  END_REASONS = %w[address_changed replaced].freeze
  # The 50 states, DC and the territories.
  US_STATES = ISO3166::Country["US"].subdivisions.transform_values(&:name)
                                    .sort_by { |_code, name| name.to_s }.to_h.freeze

  has_paper_trail

  belongs_to :user, optional: true
  belongs_to :verification, optional: true
  belongs_to :pre_reviewer, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  has_one_attached :document
  encrypts_attached :document
  has_one :sealed_document, class_name: "SealedResidencyDocument", dependent: :restrict_with_exception,
                            inverse_of: :residency_check

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :evidence_type, inclusion: { in: EVIDENCE_TYPES.keys + [MEMBER_STATEMENT] }
  validates :document, content_type: Verification::CONTENT_TYPES,
                       size: { less_than_or_equal_to: VerificationSettings.max_image_size }
  validates :us_state, inclusion: { in: US_STATES.keys }, if: :us_resident?
  validates :us_state, absence: true, unless: :us_resident?
  validates :us_resident, inclusion: { in: [true, false] }, if: :decided?
  validates :resubmission_note, presence: true, if: :needs_resubmission?
  validates :end_reason, inclusion: { in: END_REASONS }, allow_nil: true

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :document_reviews, -> { where(source: "document_review") }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
    scope name, -> { where(status: name) }
  end

  def open? = OPEN_STATUSES.include?(status)

  def identity_call? = source == "identity_call"

  def document_review? = source == "document_review"

  # When a yes result stops standing, or nil for a no result (it has no time
  # limit) or an open check.
  def expires_at
    return nil unless decided? && us_resident

    decided_at + VerificationSettings.residency_valid_for
  end

  # A decided result that still counts.
  def standing?
    return false unless decided? && ended_at.nil?

    expires_at.nil? || expires_at.future?
  end

  def document_stored? = (document.attached? || document_sealed?) && document_purged_at.nil?

  def document_sealed? = sealed_document.present? && document_purged_at.nil?

  # When the check closed: the decision, or the document rejection.
  def closed_at = decided_at || (pre_reviewed_at if needs_resubmission?)

  def evidence_label = EVIDENCE_TYPES[evidence_type] || "The member said they do not live in the US"

  def us_state_name = US_STATES[us_state]

end
