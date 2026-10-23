# frozen_string_literal: true

# A request to delete an account (proposal section 06, "Self-service
# deletion"). The member asks, or the dormancy job asks for an account with no
# sign-in for the dormancy cutoff.
#
#   pending_review -> approved -> running -> completed
#         |                         |
#         |                         +-> failed -> (retry) running
#         +-> rejected (the authenticity check failed)
#         +-> cancelled (the member, or a sign-in for a dormancy request)
#
# A human on the identity team reviews every request before the pipeline
# runs. The review is an authenticity check, not a judgment call. The review
# is due review_sla_days after the request, and the deletion is complete by
# complete_within_days (config/kyc/data_retention.yml).
#
# After completion the row stays as the log of the deletion. It holds no
# member data: user_id is empty, the receipt email is emptied once the
# receipt is sent, and the receipt lists categories, not values.
# == Schema Information
#
# Table name: deletion_requests
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  complete_by              :datetime         not null
#  completed_at             :datetime
#  receipt                  :jsonb            not null
#  receipt_email_ciphertext :text
#  receipt_sent_at          :datetime
#  requested_at             :datetime         not null
#  review_due_at            :datetime         not null
#  review_note              :text
#  reviewed_at              :datetime
#  source                   :string           default("member"), not null
#  status                   :string           default("pending_review"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  reviewed_by_id           :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_deletion_requests_on_reviewed_by_id  (reviewed_by_id)
#  index_deletion_requests_on_status          (status)
#  index_deletion_requests_on_user_id         (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (reviewed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class DeletionRequest < ApplicationRecord
  include AASM
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :delreq

  SOURCES = %w[member dormancy].freeze
  OPEN_STATES = %w[pending_review approved running failed].freeze

  has_encrypted :receipt_email

  belongs_to :user, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :runs, -> { order(:started_at, :id) }, class_name: "DeletionRun", dependent: :destroy,
                                                   inverse_of: :deletion_request

  validates :source, inclusion: { in: SOURCES }
  validates :requested_at, :review_due_at, :complete_by, presence: true
  validates :review_note, presence: true, if: -> { approved? || rejected? }
  validate :one_open_request_per_user, on: :create

  before_validation :set_deadlines, on: :create

  aasm column: :status, whiny_persistence: true do
    state :pending_review, initial: true
    state :approved
    state :running
    state :completed
    state :failed
    state :rejected
    state :cancelled

    event :approve do
      transitions from: :pending_review, to: :approved
    end

    event :reject do
      transitions from: :pending_review, to: :rejected
    end

    event :cancel do
      transitions from: %i[pending_review approved], to: :cancelled
    end

    event :start_run do
      transitions from: %i[approved failed], to: :running
    end

    event :complete do
      transitions from: :running, to: :completed
    end

    event :mark_failed do
      transitions from: :running, to: :failed
    end
  end

  scope :unfinished, -> { where(status: OPEN_STATES) }
  scope :review_overdue, -> { pending_review.where(review_due_at: ..Time.current) }

  def open? = OPEN_STATES.include?(status)

  def review_overdue? = pending_review? && review_due_at <= Time.current

  def dormancy? = source == "dormancy"

  private

  def set_deadlines
    self.requested_at ||= Time.current
    self.review_due_at ||= requested_at + DataRetention.review_sla
    self.complete_by ||= requested_at + DataRetention.complete_within
    self.receipt_email ||= user&.email
  end

  def one_open_request_per_user
    return if user_id.nil? || !DeletionRequest.unfinished.exists?(user_id:)

    errors.add(:base, I18n.t("data_handling.deletion.errors.already_open"))
  end

end
