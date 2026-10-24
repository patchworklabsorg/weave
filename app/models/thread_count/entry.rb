# frozen_string_literal: true

# One row of the Thread Count ledger (see ThreadCount).
#
# Append-only: a saved entry can't be changed or destroyed through the app. To
# take an entry back, ThreadCount::Ledger.reverse adds a "reversal" row that
# points at it, so the history shows both. The rows go only when the member's
# account is deleted (the foreign key cascades).
#
# The weight is not stored. It comes from config/thread_count.yml through the
# kind and level, so a change to the placeholder weights applies to every
# entry.
# == Schema Information
#
# Table name: thread_count_entries
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  evidence_type           :string
#  evidence_url_ciphertext :text
#  kind                    :string           not null
#  level                   :string
#  project_ref             :string
#  reason_ciphertext       :text
#  created_at              :datetime         not null
#  author_id               :bigint
#  evidence_id             :bigint
#  recorded_by_id          :bigint
#  reverses_id             :bigint
#  service_id              :bigint
#  user_id                 :bigint           not null
#
# Indexes
#
#  index_thread_count_entries_on_author_id         (author_id)
#  index_thread_count_entries_on_evidence          (evidence_type,evidence_id)
#  index_thread_count_entries_on_project_event     (service_id,project_ref,kind) UNIQUE WHERE (project_ref IS NOT NULL)
#  index_thread_count_entries_on_recorded_by_id    (recorded_by_id)
#  index_thread_count_entries_on_reverses_id       (reverses_id) UNIQUE
#  index_thread_count_entries_on_service_id        (service_id)
#  index_thread_count_entries_on_user_id           (user_id)
#  index_thread_count_entries_on_user_id_and_kind  (user_id,kind)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => users.id) ON DELETE => nullify
#  fk_rails_...  (recorded_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (reverses_id => thread_count_entries.id) ON DELETE => cascade
#  fk_rails_...  (service_id => services.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class ThreadCount::Entry < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :tce

  self.table_name = "thread_count_entries"

  VOUCH_KINDS = %w[staff_vouch board_vouch member_vouch].freeze
  PROJECT_KINDS = %w[project_approved project_exceptional project_denied project_blacklisted].freeze
  KINDS = (VOUCH_KINDS + PROJECT_KINDS + %w[moderation_case external_signal reversal]).freeze

  REASON_MAX_LENGTH = 2000

  has_encrypted :reason, :evidence_url

  belongs_to :user
  belongs_to :author, class_name: "User", optional: true
  belongs_to :recorded_by, class_name: "User", optional: true
  belongs_to :service, optional: true
  belongs_to :evidence, polymorphic: true, optional: true
  belongs_to :reverses, class_name: "ThreadCount::Entry", optional: true
  has_one :reversal, class_name: "ThreadCount::Entry", foreign_key: :reverses_id, inverse_of: :reverses, dependent: nil

  before_validation :normalize_text

  validates :kind, inclusion: { in: KINDS }
  validates :level, inclusion: { in: ->(entry) { ThreadCount.config.levels(entry.kind) } }, if: :needs_level?
  validates :level, absence: true, unless: :needs_level?
  # A person types every manual entry, so it needs a written reason. A
  # service's project event may come without one.
  validates :reason, presence: true, unless: :service_id?
  validates :reason, length: { maximum: REASON_MAX_LENGTH }
  validates :evidence_url, length: { maximum: 2000 }, format: { with: /\Ahttps?:\/\/\S+\z/, message: "must be an http or https link" },
                           allow_blank: true
  validates :reverses, presence: true, if: :reversal?
  validates :reverses_id, absence: true, unless: :reversal?
  validates :project_ref, length: { maximum: 255 }
  validate :weight_configured, on: :create

  scope :vouches, -> { where(kind: VOUCH_KINDS) }
  scope :not_reversed, -> { where.not(id: ThreadCount::Entry.unscoped.where.not(reverses_id: nil).select(:reverses_id)) }

  def readonly? = persisted? || super

  def reversal? = kind == "reversal"

  def vouch? = VOUCH_KINDS.include?(kind)

  def reversed? = self.class.exists?(reverses_id: id)

  def manual? = service_id.nil?

  private

  def needs_level? = %w[staff_vouch moderation_case external_signal].include?(kind)

  def normalize_text
    self.reason = reason.to_s.strip.presence
    self.evidence_url = evidence_url.to_s.strip.presence
    self.project_ref = project_ref.to_s.strip.presence
  end

  def weight_configured
    return if !KINDS.include?(kind) || ThreadCount.config.weight?(kind, level)

    errors.add(:level, "has no weight in config/thread_count.yml")
  end

end
