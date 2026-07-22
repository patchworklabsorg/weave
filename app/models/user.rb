# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  acknowledged_over_13_at  :datetime
#  birthday                 :date
#  confirmation_sent_at     :datetime
#  confirmation_token       :string
#  email                    :string           not null
#  email_confirmed_at       :datetime
#  first_name               :string           not null
#  is_board                 :boolean          default(FALSE), not null
#  is_contractor            :boolean          default(FALSE), not null
#  is_staff                 :boolean          default(FALSE), not null
#  last_name                :string           not null
#  locked_at                :datetime
#  magic_link_expires_at    :datetime
#  magic_link_sent_at       :datetime
#  magic_link_token         :string
#  magic_link_used_at       :datetime
#  password_digest          :string           not null
#  phone_number             :string
#  role                     :integer          default("user"), not null
#  session_duration_seconds :integer          default(2592000), not null
#  slack_birthday           :date
#  slack_city               :string
#  slack_cost_center        :string
#  slack_country            :string
#  slack_department         :string
#  slack_display_name       :string
#  slack_division           :string
#  slack_github             :string
#  slack_joined_at          :datetime
#  slack_linkedin           :string
#  slack_organization       :string
#  slack_phone              :string
#  slack_profile_image_url  :string
#  slack_profile_synced_at  :datetime
#  slack_pronouns           :string
#  slack_role_description   :text
#  slack_start_date         :date
#  slack_state              :string
#  slack_status_emoji       :string
#  slack_status_text        :string
#  slack_title              :string
#  slack_website            :string
#  status                   :enum             default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  manager_id               :bigint
#  p_id                     :string           not null
#  slack_id                 :string
#  slack_manager_id         :string
#
# Indexes
#
#  index_users_on_confirmation_token  (confirmation_token) UNIQUE
#  index_users_on_email               (email) UNIQUE
#  index_users_on_magic_link_token    (magic_link_token) UNIQUE
#  index_users_on_manager_id          (manager_id)
#  index_users_on_p_id                (p_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (manager_id => users.id)
#
require "securerandom"

class User < ApplicationRecord
  include AASM

  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :usr

  # set flipper id to p_id
  def flipper_id
    p_id
  end

  # Generate a random password guaranteed to satisfy #password_complexity
  # (at least one uppercase, lowercase, digit, and special character, length >= 8).
  # Used for accounts that only ever authenticate via magic links (e.g. signups
  # and users provisioned from Slack).
  def self.generate_secure_password
    specials = "!@#$%^&*()_+-=[]{}|;:,.<>?".chars
    required = [
      ("A".."Z").to_a.sample,
      ("a".."z").to_a.sample,
      SecureRandom.random_number(10).to_s,
      specials.sample
    ]
    filler = SecureRandom.alphanumeric(20).chars
    (required + filler).shuffle.join
  end

  has_paper_trail
  has_secure_password

  has_many :visits, class_name: "Ahoy::Visit", dependent: :destroy
  has_many :user_sessions, class_name: "User::Session", dependent: :destroy

  # Address associations
  has_many :addresses, as: :addressable, dependent: :destroy, class_name: "UserAddress", inverse_of: :addressable
  has_one :shipping_address, -> { where(address_type: "Shipping") }, as: :addressable, class_name: "UserAddress", dependent: :destroy, inverse_of: :addressable
  has_one :billing_address, -> { where(address_type: "Billing") }, as: :addressable, class_name: "UserAddress", dependent: :destroy, inverse_of: :addressable

  # Manager/Reports relationships (only for staff/contractors)
  belongs_to :manager, class_name: "User", optional: true
  has_many :reports, class_name: "User", foreign_key: "manager_id", dependent: :nullify

  # OAuth tokens/grants issued to this user as the resource owner.
  # Destroyed with the user so hard-deletes don't raise foreign key violations.
  has_many :oauth_access_grants, class_name: "Doorkeeper::AccessGrant",
                                 foreign_key: :resource_owner_id, dependent: :destroy, inverse_of: false
  has_many :oauth_access_tokens, class_name: "Doorkeeper::AccessToken",
                                 foreign_key: :resource_owner_id, dependent: :destroy, inverse_of: false

  # Records this user created. Nullify on delete so the records survive.
  has_many :created_services, class_name: "Service",
                              foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by
  has_many :created_service_keys, class_name: "Service::Key",
                                  foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by
  has_many :created_service_webhooks, class_name: "Service::Webhook",
                                      foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by

  accepts_nested_attributes_for :shipping_address, :billing_address, allow_destroy: true

  before_save :set_address_types
  after_create :send_confirmation_email

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

  scope :user, -> { where(role: %w[user admin superadmin owner]) }
  scope :admin, -> { where(role: %w[admin superadmin owner]) }
  scope :superadmin, -> { where(role: %w[superadmin owner]) }
  scope :owner, -> { where(role: "owner") }

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
    "#{first_name&.[](0)}#{last_name&.[](0)}"
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


  def can_authenticate?
    # Check if user can authenticate (not locked)
    !locked?
  end

  def can_impersonate?
    # Determines if THIS user can impersonate others
    # Only active, non-pretending admins and above can impersonate
    return false unless can_authenticate?

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

  def send_magic_link
    # Generate magic link token and set expiration
    self.magic_link_token = SecureRandom.urlsafe_base64(32)
    self.magic_link_expires_at = 15.minutes.from_now
    self.magic_link_sent_at = Time.current
    self.magic_link_used_at = nil # Clear any previous usage

    if save
      MagicLinkJob.perform_later(self)
      true
    else
      Rails.logger.error "Failed to save magic link for user #{email}: #{errors.full_messages.join(', ')}"
      false
    end
  end

  def magic_link_valid?
    magic_link_token.present? &&
      magic_link_expires_at.present? &&
      magic_link_expires_at > Time.current &&
      magic_link_used_at.nil?
  end

  # Securely verify if the provided token matches this user's magic link token
  # Uses constant-time comparison to prevent timing attacks
  def magic_link_token_matches?(provided_token)
    return false if magic_link_token.blank? || provided_token.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      magic_link_token,
      provided_token
    )
  end

  def consume_magic_link_token!
    return false unless magic_link_valid?

    self.magic_link_used_at = Time.current
    self.magic_link_token = nil
    self.magic_link_expires_at = nil
    save!
  end

  def regen_pid
    old_pid = p_id
    self.p_id = nil
    generate_p_id
    save!
    Rails.logger.info "Regenerated p_id for user #{email}: #{old_pid} -> #{p_id}"
    p_id
  end

  def email_verified?
    email_confirmed_at.present?
  end

  def verify_email
    update!(email_confirmed_at: Time.current, confirmation_token: nil)
  end

  def send_confirmation_email
    generate_confirmation_token
    self.confirmation_sent_at = Time.current
    save!

    # Queue email job
    ConfirmationEmailJob.perform_later(self)
    true
  rescue => e
    Rails.logger.error "Failed to send confirmation email for user #{email}: #{e.message}"
    false
  end

  def confirmation_period_valid?
    return false if confirmation_sent_at.nil?

    Time.current - confirmation_sent_at < 5.minutes
  end

  def admin?
    # Override enum method to include owner, superadmin, and admin roles
    %w[admin superadmin owner].include?(role)
  end

  def superadmin?
    # Override enum method to include owner and superadmin roles
    %w[superadmin owner].include?(role)
  end

  def is_manager_or_manageable?
    # Users who are staff or contractors can have/be managers
    is_staff || is_contractor
  end

  # Membership attributes. `role` governs access (user/admin/superadmin/owner);
  # staff and board are orthogonal attributes that configure capabilities, not
  # access tiers. A plain member with no elevated role is a "community member".
  def board? = is_board
  def staff? = is_staff
  def community_member? = user?

  # Human-facing membership label for profile/admin display.
  def membership_label
    labels = []
    labels << "Board member" if is_board
    labels << "Staff" if is_staff
    labels << "Contractor" if is_contractor
    labels << "Community member" if labels.empty?
    labels.join(" · ")
  end

  # Make Rails URL helpers use p_id instead of id
  def to_param
    p_id
  end

  def username
    # first three letters of first name plus entire last name, all lowercase
    "#{first_name[0, 3]}#{last_name}".downcase
  end

  private

  def generate_confirmation_token
    self.confirmation_token = SecureRandom.urlsafe_base64(32)
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

  def generate_p_id(hex_length: 9)
    # Generates a global unique ID for the user.
    # Format: PWL{random digit}{hex_length random hex characters, all uppercase}
    # Example: PWL5A1B2C3D4

    numeric_first = SecureRandom.random_number(10).to_s
    bytes_needed = (hex_length / 2.0).ceil
    hex_chars = SecureRandom.hex(bytes_needed).upcase[0, hex_length]
    self.p_id ||= "PWL#{numeric_first}#{hex_chars}"
  end

  def set_address_types
    shipping_address&.address_type = "Shipping" if shipping_address.present?
    billing_address&.address_type = "Billing" if billing_address.present?
  end

end
