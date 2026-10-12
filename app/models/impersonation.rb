# frozen_string_literal: true

# == Schema Information
#
# Table name: impersonations
# Database name: primary
#
#  id         :bigint           not null, primary key
#  denied     :boolean          default(FALSE), not null
#  end_reason :string
#  ended_at   :datetime
#  ip         :string
#  started_at :datetime         not null
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  admin_id   :bigint
#  user_id    :bigint
#
# Indexes
#
#  index_impersonations_on_admin_id  (admin_id)
#  index_impersonations_on_user_id   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (admin_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#

# Audit record of an admin signing in as another user. Admin::UsersController
# starts one on impersonate (or records a denied attempt), and it ends when the
# admin stops impersonating or logs out. Only admins can see these rows, on the
# admin user page. They are never shown to the impersonated user.
class Impersonation < ApplicationRecord
  END_REASONS = %w[stopped logged_out].freeze

  belongs_to :admin, class_name: "User", optional: true
  belongs_to :user, optional: true

  validates :started_at, presence: true
  validates :end_reason, inclusion: { in: END_REASONS }, allow_nil: true

  scope :recent_first, -> { order(started_at: :desc) }

  def self.start!(admin:, user:, request:, denied: false)
    create!(
      admin: admin,
      user: user,
      started_at: Time.current,
      ended_at: (Time.current if denied),
      denied: denied,
      ip: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255).presence
    )
  end

  def end!(reason)
    return if ended_at.present?

    update!(ended_at: Time.current, end_reason: reason)
  end

  def active?
    !denied? && ended_at.nil?
  end

  def duration
    ended_at - started_at if ended_at && !denied?
  end

end
