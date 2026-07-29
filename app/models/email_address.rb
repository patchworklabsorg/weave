# frozen_string_literal: true

# == Schema Information
#
# Table name: email_addresses
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  confirmation_sent_at :datetime
#  confirmation_token   :string
#  confirmed_at         :datetime
#  email                :string           not null
#  is_primary           :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_email_addresses_on_confirmation_token  (confirmation_token) UNIQUE
#  index_email_addresses_on_email               (email) UNIQUE
#  index_email_addresses_on_user_id             (user_id)
#  index_email_addresses_one_primary_per_user   (user_id) UNIQUE WHERE is_primary
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "securerandom"

class EmailAddress < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :eml

  has_paper_trail

  belongs_to :user

  validates :email, presence: true, uniqueness: true
  validates_email_format_of :email
  validates :email, undisposable: { message: "Sorry, but we do not accept disposable email providers." }
  normalizes :email, with: ->(email) { email.strip.downcase }
  validate :email_not_taken_by_another_user

  scope :confirmed, -> { where.not(confirmed_at: nil) }

  before_destroy :ensure_not_primary

  def confirmed?
    confirmed_at.present?
  end

  def primary?
    is_primary
  end

  def confirm!
    update!(confirmed_at: Time.current, confirmation_token: nil)
  end

  # Promote this address to the user's primary email. Only confirmed addresses
  # can become primary — the users.email column stays the canonical login
  # identifier, and User#sync_primary_email_address flips the is_primary flags.
  def make_primary!
    unless confirmed?
      errors.add(:base, "Email address must be confirmed before it can be made primary.")
      return false
    end
    return true if primary?

    user.update!(email: email, email_confirmed_at: confirmed_at)
    reload
    true
  end

  def send_confirmation_email
    self.confirmation_token = SecureRandom.urlsafe_base64(32)
    self.confirmation_sent_at = Time.current
    save!

    EmailAddressConfirmationJob.perform_later(self)
    true
  rescue => e
    Rails.logger.error "Failed to send confirmation email for email address #{id}: #{e.message}"
    false
  end

  def confirmation_period_valid?
    return false if confirmation_sent_at.nil?

    Time.current - confirmation_sent_at < 5.minutes
  end

  private

  def email_not_taken_by_another_user
    return if email.blank?

    errors.add(:email, "has already been taken") if User.where(email: email).where.not(id: user_id).exists?
  end

  def ensure_not_primary
    return unless primary?

    errors.add(:base, "Primary email address cannot be removed. Make another email primary first.")
    throw :abort
  end

end
