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
#  legal_first_name         :string
#  legal_last_name          :string
#  locked_at                :datetime
#  password_digest          :string           not null
#  phone_number             :string
#  pronouns                 :string
#  role                     :integer          default("user"), not null
#  session_duration_seconds :integer          default(2592000), not null
#  slack_birthday           :date
#  slack_city               :string
#  slack_coc_accepted_at    :datetime
#  slack_cost_center        :string
#  slack_country            :string
#  slack_department         :string
#  slack_display_name       :string
#  slack_division           :string
#  slack_github             :string
#  slack_invited_at         :datetime
#  slack_joined_at          :datetime
#  slack_linkedin           :string
#  slack_membership         :string           default("pending"), not null
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
  has_many :magic_links, class_name: "User::MagicLink", dependent: :destroy

  # All email addresses belonging to this user. users.email stays the canonical
  # primary address and is mirrored into this table (is_primary flag).
  # delete_all so hard-deleting a user isn't blocked by the primary-address
  # destroy guard on EmailAddress.
  has_many :email_addresses, dependent: :delete_all

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
  after_create :create_primary_email_address
  after_update :sync_primary_email_address, if: -> { saved_change_to_email? || saved_change_to_email_confirmed_at? }
  after_update :revoke_oauth_access!, if: :lost_ability_to_authenticate?

  enum :role, {
    user: 0,
    admin: 1,
    superadmin: 2,
    owner: 3
  }

  # Full membership of the Patchwork Labs Slack: in the workspace as a regular
  # member, not a guest. Everyone starts `pending` and becomes a `member` once
  # Slack reports them as one (see .slack_membership_for), which for new
  # signups means after they accept the code of conduct. OAuth clients read it
  # as the `slack_member` claim.
  enum :slack_membership, { pending: "pending", member: "member" }, prefix: :slack

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
  validate :email_not_claimed_by_another_user
  normalizes :legal_first_name, :legal_last_name, with: ->(name) { name.strip.presence }
  validates :legal_first_name, :legal_last_name, length: { maximum: 100 }
  validates :password, presence: true, length: { minimum: 8 }, if: lambda {
    new_record? || password.present?
  }
  validate :password_complexity, if: lambda {
    new_record? || password.present?
  }
  validate :validate_phone_number, if: -> { phone_number.present? }
  before_save :parse_phone_number
  # PWL{digit}{9 uppercase hex characters}, e.g. PWL5A1B2C3D4.
  #
  # Uppercase only, matching what `generate_p_id` has emitted since the column
  # existed. p_id is the OIDC `sub`: relying parties compare it byte for byte to
  # decide who someone is, so one identity must not have two spellings. The
  # previous /[a-fA-F0-9]/ admitted a lowercase variant that nothing produced
  # and no consumer would have matched.
  validates :p_id, presence: true, uniqueness: true, length: { is: 13 }, format: {
    with: /\APWL\d[A-F0-9]{9}\z/,
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
    # Display names capitalized (many Slack-imported names arrive lowercase).
    # Only upcase the first letter of each word so intentional casing like
    # "McDonald" or "O'Brien" is preserved.
    "#{first_name} #{last_name}".strip.gsub(/\b\p{L}/, &:upcase)
  end

  def name
    full_name
  end

  # Legal name is stored separately from the preferred name (first_name /
  # last_name) and only used where a legal name is required (e.g. contracts,
  # payroll). Falls back to the preferred name when unset.
  def legal_name?
    legal_first_name.present? || legal_last_name.present?
  end

  def legal_full_name
    return full_name unless legal_name?

    "#{legal_first_name.presence || first_name} #{legal_last_name.presence || last_name}"
  end

  def initials
    "#{first_name&.[](0)}#{last_name&.[](0)}".upcase
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


  # Whether this account may sign in at all: unlocked and in the active status.
  # (User#active? is overloaded for "recently seen", so compare the status
  # column directly.)
  def can_authenticate?
    !locked? && status.to_s == "active"
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

  # Revoke every OAuth access token (and with it, its refresh token) and every
  # unredeemed authorization code issued to this user, across all clients.
  #
  # Runs automatically whenever an update leaves the account unable to sign in
  # (locked, suspended, deactivated): ending the Weave sessions alone leaves
  # other apps working off access tokens for up to two hours and, worse, off
  # refresh tokens that never expire, so a locked account could keep minting
  # new access indefinitely.
  def revoke_oauth_access!
    now = Time.current
    oauth_access_tokens.where(revoked_at: nil).update_all(revoked_at: now) # rubocop:disable Rails/SkipsModelValidations
    oauth_access_grants.where(revoked_at: nil).update_all(revoked_at: now) # rubocop:disable Rails/SkipsModelValidations
  end

  # Issues a fresh link and mails it. Existing unused links stay valid — see
  # User::MagicLink for why.
  def send_magic_link(requested_ip: nil)
    link = User::MagicLink.issue!(self, requested_ip: requested_ip)
    MagicLinkJob.perform_later(self, link.token)
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to issue magic link for user #{email}: #{e.record.errors.full_messages.join(', ')}"
    false
  end

  # Clicking a link that was only ever delivered to this address demonstrates
  # exactly what the confirmation email asks for, so don't ask for it a second
  # time. Accounts created by import have no confirmation behind them, and
  # without this every one of them has to collect a second email before they
  # can use the account at all.
  def confirm_email_from_magic_link!
    return if email_verified?

    verify_email
  end

  def regen_pid
    old_pid = p_id
    self.p_id = nil
    generate_p_id
    save!
    Rails.logger.info "Regenerated p_id for user #{email}: #{old_pid} -> #{p_id}"
    p_id
  end

  # Look a user up by any email that can identify them: the primary
  # (users.email) or any confirmed additional address. Unconfirmed additional
  # addresses never resolve — they aren't proven to belong to the user yet.
  def self.find_for_any_email(value)
    normalized = value.to_s.strip.downcase
    return nil if normalized.blank?

    find_by(email: normalized) || EmailAddress.confirmed.find_by(email: normalized)&.user
  end

  def primary_email_address
    email_addresses.find_by(is_primary: true)
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

  # In the Slack workspace already — a slack_id is only ever set by syncing
  # against a real workspace member (invite acceptance, team-join webhook, or
  # profile sync), so its presence means they joined, whether or not Weave
  # sent the invite. They can still be a guest: see #slack_member?.
  def in_slack_workspace? = slack_id.present?

  # Where this person is in joining the Slack. Drives the /slack onboarding
  # page. Each step is the next thing the person must do.
  def slack_onboarding_step
    return :member if slack_member?
    return :awaiting_promotion if in_slack_workspace? && slack_coc_accepted_at.present?
    return :accept_code_of_conduct if in_slack_workspace?
    return :accept_invite if slack_invited_at.present?

    :request_invite
  end

  # The membership a Slack user object (from users.info, users.lookupByEmail,
  # users.list or a team_join/user_change event) entitles its owner to. Guests
  # and deactivated accounts are not members.
  def self.slack_membership_for(slack_user)
    full = !slack_user["deleted"] && !slack_user["is_restricted"] && !slack_user["is_ultra_restricted"]
    full ? "member" : "pending"
  end

  # Records the membership Slack reports for this person. Skips the write when
  # nothing changed, and bumps updated_at so the OIDC updated_at claim moves.
  def apply_slack_membership!(slack_user)
    # A lookup by email can find a different Slack account from the one
    # linked here (e.g. an old account under a former address). Only the
    # linked account decides membership.
    return if slack_id.present? && slack_user["id"].present? && slack_user["id"] != slack_id

    membership = self.class.slack_membership_for(slack_user)
    return if slack_membership == membership

    update_columns(slack_membership: membership, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

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

  def lost_ability_to_authenticate?
    (saved_change_to_locked_at? || saved_change_to_status?) && !can_authenticate?
  end

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

  def validate_phone_number
    return if Phonelib.parse(phone_number).valid?

    errors.add(:phone_number, "is not a valid phone number (include your area code)")
  end

  def parse_phone_number
    return if phone_number.blank?

    parsed = Phonelib.parse(phone_number)
    self.phone_number = parsed.full_e164 if parsed.valid?
  end

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

  def email_not_claimed_by_another_user
    return if email.blank?

    claimed = EmailAddress.where(email: email)
    claimed = claimed.where.not(user_id: id) if id.present?
    errors.add(:email, "has already been taken") if claimed.exists?
  end

  def create_primary_email_address
    email_addresses.create!(email: email, is_primary: true, confirmed_at: email_confirmed_at)
  end

  # Mirror users.email (and its confirmation state) into email_addresses so the
  # row matching the canonical address is always the confirmed/primary one.
  # When the email changes, the old address is kept as a secondary.
  def sync_primary_email_address
    transaction do
      address = email_addresses.find_or_initialize_by(email: email)
      # Clear any other primary first so the partial unique index isn't violated.
      email_addresses.where(is_primary: true).where.not(id: address.id).update_all(is_primary: false) # rubocop:disable Rails/SkipsModelValidations
      address.is_primary = true
      # Never downgrade an already-confirmed address (e.g. a Slack-driven email
      # change resets email_confirmed_at, but the address may already be proven).
      unless email_confirmed_at.nil? && address.confirmed_at.present?
        address.confirmed_at = email_confirmed_at
      end
      address.confirmation_token = nil if address.confirmed_at.present?
      address.save!
    end
  end

end
