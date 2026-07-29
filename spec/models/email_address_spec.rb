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
require "rails_helper"

RSpec.describe EmailAddress, type: :model do
  let(:user) { create(:user) }

  describe "primary email sync from User" do
    it "creates a primary email address row on user creation" do
      address = user.email_addresses.find_by(is_primary: true)
      expect(address).to be_present
      expect(address.email).to eq(user.email)
      expect(address.confirmed?).to be(false)
    end

    it "mirrors email confirmation onto the primary address" do
      user.verify_email
      address = user.email_addresses.find_by(is_primary: true)
      expect(address.confirmed_at).to eq(user.email_confirmed_at)
    end

    it "keeps the old address as a secondary when the primary email changes" do
      old_email = user.email
      user.update!(email: "new-primary@example.com", email_confirmed_at: nil)

      primary = user.email_addresses.find_by(is_primary: true)
      expect(primary.email).to eq("new-primary@example.com")
      expect(user.email_addresses.pluck(:email)).to include(old_email)
      expect(user.email_addresses.where(is_primary: true).count).to eq(1)
    end

    it "does not un-confirm an already-confirmed address when it becomes primary unverified" do
      secondary = create(:email_address, :confirmed, user: user, email: "second@example.com")
      user.update!(email: "second@example.com", email_confirmed_at: nil)

      expect(secondary.reload).to be_primary
      expect(secondary.confirmed?).to be(true)
    end
  end

  describe "validations" do
    it "normalizes email" do
      address = create(:email_address, user: user, email: "  MiXeD@Example.COM ")
      expect(address.email).to eq("mixed@example.com")
    end

    it "rejects an email already used in email_addresses" do
      create(:email_address, user: user, email: "taken@example.com")
      dup = build(:email_address, user: create(:user), email: "taken@example.com")
      expect(dup).not_to be_valid
      expect(dup.errors[:email]).to include("has already been taken")
    end

    it "rejects an email that is another user's account email" do
      other = create(:user)
      address = build(:email_address, user: user, email: other.email)
      expect(address).not_to be_valid
      expect(address.errors[:email]).to include("has already been taken")
    end

    it "prevents a user from taking an email claimed by another user's addresses" do
      create(:email_address, user: user, email: "claimed@example.com")
      other = build(:user, email: "claimed@example.com")
      expect(other).not_to be_valid
      expect(other.errors[:email]).to include("has already been taken")
    end
  end

  describe "#confirm!" do
    it "sets confirmed_at and clears the token" do
      address = create(:email_address, :with_confirmation_token, user: user)
      address.confirm!
      expect(address.confirmed?).to be(true)
      expect(address.confirmation_token).to be_nil
    end
  end

  describe "#make_primary!" do
    it "refuses unconfirmed addresses" do
      address = create(:email_address, user: user)
      expect(address.make_primary!).to be(false)
      expect(address.errors[:base]).to be_present
      expect(user.reload.email).not_to eq(address.email)
    end

    it "promotes a confirmed address and demotes the old primary" do
      old_primary_email = user.email
      address = create(:email_address, :confirmed, user: user)

      expect(address.make_primary!).to be(true)
      expect(user.reload.email).to eq(address.email)
      expect(user.email_confirmed_at).to eq(address.confirmed_at)
      expect(address.reload).to be_primary
      expect(user.email_addresses.find_by(email: old_primary_email)).not_to be_primary
    end
  end

  describe "destroy" do
    it "cannot destroy the primary address" do
      primary = user.email_addresses.find_by(is_primary: true)
      expect(primary.destroy).to be(false)
      expect(user.email_addresses.where(email: primary.email)).to exist
    end

    it "destroys secondary addresses" do
      address = create(:email_address, user: user)
      expect { address.destroy! }.to change { user.email_addresses.count }.by(-1)
    end
  end

  describe "#send_confirmation_email" do
    it "generates a token and enqueues the job" do
      address = create(:email_address, user: user)
      expect {
        expect(address.send_confirmation_email).to be(true)
      }.to have_enqueued_job(EmailAddressConfirmationJob)
      expect(address.confirmation_token).to be_present
      expect(address.confirmation_sent_at).to be_present
    end
  end

  describe "User.find_for_any_email" do
    it "finds by primary email" do
      expect(User.find_for_any_email(user.email.upcase)).to eq(user)
    end

    it "finds by confirmed secondary email" do
      address = create(:email_address, :confirmed, user: user)
      expect(User.find_for_any_email(address.email)).to eq(user)
    end

    it "does not find by unconfirmed secondary email" do
      address = create(:email_address, user: user, email: "unconfirmed@example.com")
      expect(User.find_for_any_email(address.email)).to be_nil
    end

    it "returns nil for blank input" do
      expect(User.find_for_any_email(nil)).to be_nil
      expect(User.find_for_any_email("  ")).to be_nil
    end
  end
end
