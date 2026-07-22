# frozen_string_literal: true

# == Schema Information
#
# Table name: services
# Database name: primary
#
#  id            :bigint           not null, primary key
#  description   :text
#  name          :string           not null
#  status        :string           default("active"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint           not null
#
# Indexes
#
#  index_services_on_created_by_id  (created_by_id)
#  index_services_on_name           (name) UNIQUE
#  index_services_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#
class Service < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :srvc

  # Associations
  belongs_to :created_by, class_name: "User"
  has_many :keys, class_name: "Service::Key", dependent: :destroy
  has_many :webhooks, class_name: "Service::Webhook", dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[active inactive suspended] }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :suspended, -> { where(status: "suspended") }

  # Methods
  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def suspended?
    status == "suspended"
  end

  def activate!
    update!(status: "active")
  end

  def deactivate!
    update!(status: "inactive")
  end

  def suspend!
    update!(status: "suspended")
  end
end
