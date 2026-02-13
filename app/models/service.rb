# frozen_string_literal: true

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
