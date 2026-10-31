# frozen_string_literal: true

# A member asks for access to a restricted OAuth app from the "You don't have
# access" page or the app launcher. The app names the group that gives access
# (Doorkeeper::Application#access_request_group), and the request keeps that
# group: a manager of the group, or a superadmin, decides. Approval adds the
# member to the group. See AccessRequests for the flow and AccessRequestPolicy
# for who may decide.
#
# A member has at most one pending request for each app.
# == Schema Information
#
# Table name: access_requests
# Database name: primary
#
#  id             :bigint           not null, primary key
#  decided_at     :datetime
#  reason         :text             not null
#  status         :string           default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  application_id :bigint           not null
#  decided_by_id  :bigint
#  group_id       :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_access_requests_on_application_id          (application_id)
#  index_access_requests_on_decided_by_id           (decided_by_id)
#  index_access_requests_on_group_id_and_status     (group_id,status)
#  index_access_requests_on_user_id_and_created_at  (user_id,created_at)
#  index_access_requests_one_pending                (user_id,application_id) UNIQUE WHERE ((status)::text = 'pending'::text)
#
# Foreign Keys
#
#  fk_rails_...  (application_id => oauth_applications.id) ON DELETE => cascade
#  fk_rails_...  (decided_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (group_id => groups.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class AccessRequest < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :areq

  has_paper_trail

  REASON_MAX_LENGTH = 1000

  # `cancelled`: closed with no decision, because the app's request group
  # changed or the group was deleted (see AccessRequests.cancel_stale!).
  enum :status, { pending: "pending", approved: "approved", denied: "denied", cancelled: "cancelled" },
       default: "pending", validate: true

  belongs_to :user
  belongs_to :application, class_name: "Doorkeeper::Application"
  # The group is soft-deleted, so a request keeps it for the history.
  belongs_to :group, -> { with_deleted }, inverse_of: false
  belongs_to :decided_by, class_name: "User", optional: true

  validates :reason, presence: true, length: { maximum: REASON_MAX_LENGTH }
  validate :one_pending_request_per_app, if: :pending?

  scope :newest_first, -> { order(created_at: :desc) }

  def decided? = !pending?

  private

  # The partial unique index has the last word. This gives a form error first.
  def one_pending_request_per_app
    others = AccessRequest.pending.where(user_id: user_id, application_id: application_id).where.not(id: id)
    errors.add(:base, "You already asked for access to this app.") if others.exists?
  end

end
