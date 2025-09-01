# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                       :bigint           not null, primary key
#  access_level             :enum             default("user"), not null
#  api_access_level         :enum             default("user"), not null
#  confirmation_sent_at     :datetime
#  confirmation_token       :string
#  email                    :string           not null
#  email_verified           :boolean          default(FALSE)
#  email_verified_at        :datetime
#  first_name               :string           not null
#  last_name                :string           not null
#  locked_at                :datetime
#  magic_link_expires_at    :datetime
#  magic_link_sent_at       :datetime
#  magic_link_token         :string
#  magic_link_used_at       :datetime
#  password_digest          :string           not null
#  pd_dev                   :boolean          default(FALSE), not null
#  pretend_is_not_admin     :boolean          default(FALSE), not null
#  services_used            :integer          default([]), is an Array
#  session_duration_seconds :integer          default(2592000), not null
#  signup_service           :integer
#  staff                    :boolean          default(FALSE), not null
#  status                   :enum             default("active"), not null
#  username                 :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  pd_id                    :string           not null
#
# Indexes
#
#  index_users_on_confirmation_token  (confirmation_token) UNIQUE
#  index_users_on_email               (email) UNIQUE
#  index_users_on_magic_link_token    (magic_link_token) UNIQUE
#  index_users_on_pd_id               (pd_id) UNIQUE
#
class User < ApplicationRecord
  include AASM

  # set flipper id to pd_id
  def flipper_id
    pd_id
  end

  has_paper_trail
  has_secure_password

  has_many :visits, class_name: "Ahoy::Visit", dependent: :destroy
  has_many :user_sessions, class_name: "User::Session", dependent: :destroy

  enum :role, {
    user: 0,
    admin: 1,
    superadmin: 2,
    owner: 3
  }

  scope :last_seen_within, ->(ago) { joins(:user_sessions).where(user_sessions: { last_seen_at: ago.. }).distinct }
  scope :currently_online, -> { last_seen_within(15.minutes.ago) }
  scope :active, -> { last_seen_within(30.days.ago) }
  def active? = last_seen_at && (last_seen_at >= 30.days.ago)

  scope :user, -> { where(access_level: %w[user admin superadmin owner]) }
  scope :admin, -> { where(access_level: %w[admin superadmin owner]) }
  scope :superadmin, -> { where(access_level: %w[superadmin owner]) }
  scope :owner, -> { where(access_level: 'owner') }

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, uniqueness: true
  validates_email_format_of :email
  validates :email, undisposable: { message: "Sorry, but we do not accept disposable email providers." }
  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :password, presence: true, length: { minimum: 8 }, if: lambda {
    new_record? || password.present?
  }
  validate :password_complexity, if: lambda {
    new_record? || password.present?
  }
  validates :p_id, presence: true, uniqueness: true, length: { is: 13 }, format: {
    # format is PWL{digit}{9 alphanumeric characters}
    with: /\APWL\d[a-fA-F0-9]{9}\z/,
    message: "PWL ID failed format validation"
  }

  before_validation :generate_p_id, on: :create

  # State machine for user status
  aasm column: :status do
    state :active, initial: true
    state :suspended
    state :deactivated

    event :suspend do
      transitions from: :active, to: :suspended
    end

    event :reactivate do
      transitions from: %i[suspended deactivated], to: :active
    end

    event :deactivate do
      transitions from: %i[active suspended], to: :deactivated
    end
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def name
    full_name
  end

  def initials
    "#{first_name[0]}#{last_name[0]}"
  end

  def is_impersonatable?(impersonator)
    # Cannot impersonate yourself
    return false if self == impersonator

    # Only admins and above can impersonate
    return false unless impersonator.admin?

    # Cannot impersonate other admins or higher
    !admin?
  end

  def is_viewable?(viewer)
    # you can view yourself
    return true if self == viewer

    # Only admins and above can view other users
    return false unless viewer.admin?

    # Admins can view all non-admins
    return true if viewer.admin? && !admin?

    # Superadmins can view admins and below
    return true if viewer.superadmin? && !superadmin? && !owner?

    # Owners can view everyone
    return true if viewer.owner?

    false
  end


  def can_impersonate?
    # Determines if THIS user can impersonate others
    # Only active, non-pretending admins and above can impersonate
    return false unless can_authenticate? && !pretend_is_not_admin

    admin?
  end

  def impersonatable?
    # This is a convenience method for views - checks if user is impersonatable by the current admin
    # This should be overridden by passing current_user context, but provides basic check
    !admin?
  end

  def last_seen_at
    user_sessions.maximum(:last_seen_at)
  end

  def last_login_at
    user_sessions.maximum(:created_at)
  end

  def locked?
    locked_at.present?
  end

  def lock!
    update!(locked_at: Time.zone.now)

    # Invalidate all sessions
    user_sessions.destroy_all
  end

  def unlock!
    update!(locked_at: nil)
  end

  private

  def admin_override_pretend?
    ["admin"].include?(self.access_level)
  end

  def make_trusted!
    trusted!
  end

  def make_admin!
    admin!
  end

  def make_superadmin!
    superadmin!
  end

  def make_owner!
    owner!
  end

  def remove_trusted!
    user!
  end

  private

  def password_complexity
    return if password.blank?

    errors.add(:password, "must contain at least one uppercase letter") unless password.match(/[A-Z]/)
    errors.add(:password, "must contain at least one lowercase letter") unless password.match(/[a-z]/)
    errors.add(:password, "must contain at least one number") unless password.match(/\d/)
    errors.add(:password, "must contain at least one special character (!@#$%^&*()_+-=[]{}|;:,.<>?)") unless password.match(/[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/)
  end

  def generate_p_id
    # Generates global unique ID for the user
    # Format: PWL{random digit}{9 random hex characters}
    # EXAMPLE: PWL5A1B2C3D

    random_digits = SecureRandom.hex(5) # Generates 10 hex characters
    numeric_first = rand(0..9).to_s # The first character is a random digit
    remaining_chars = random_digits[1..-1] # Remaining 9 characters

    self.p_id ||= "PWL#{numeric_first}#{remaining_chars}"
  end

end
