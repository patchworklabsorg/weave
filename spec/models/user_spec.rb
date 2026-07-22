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
require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    # Provide a fully valid record so shoulda's uniqueness matcher can persist
    # the "existing" record it compares against. The matcher saves that record
    # with `validate: false`, which skips the before_validation p_id generation,
    # so a valid p_id must be supplied here (first_name/last_name are NOT NULL).
    subject { build(:user, p_id: "PWL0ABCDEF123") }

    it { should validate_presence_of(:first_name) }
    it { should validate_presence_of(:last_name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }

    it "validates email format" do
      user = build(:user, email: "invalid-email")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("does not appear to be a valid email address")
    end

    it "validates password complexity" do
      user = build(:user, password: "weak", password_confirmation: "weak")
      expect(user).not_to be_valid
    end
  end

  describe "associations" do
    it { should have_many(:visits).class_name("Ahoy::Visit") }
    it { should have_many(:user_sessions).class_name("User::Session") }
    it { should have_many(:addresses) }
    it { should have_one(:shipping_address) }
    it { should have_one(:billing_address) }
  end

  describe "callbacks" do
    it "sends confirmation email after creation" do
      expect {
        create(:user)
      }.to have_enqueued_job(ConfirmationEmailJob)
    end
  end

  describe "#full_name" do
    it "returns first name and last name" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.full_name).to eq("John Doe")
    end
  end

  describe "#initials" do
    it "returns first letter of first and last name" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.initials).to eq("JD")
    end

    it "handles nil names safely" do
      user = User.new(first_name: nil, last_name: nil)
      expect(user.initials).to eq("")
    end
  end

  describe "#username" do
    it "returns first three letters of first name plus last name" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.username).to eq("johdoe")
    end

    it "handles short first names" do
      user = build(:user, first_name: "Jo", last_name: "Doe")
      expect(user.username).to eq("jodoe")
    end
  end

  describe "#email_verified?" do
    it "returns false when email_confirmed_at is nil" do
      user = build(:user, email_confirmed_at: nil)
      expect(user.email_verified?).to be false
    end

    it "returns true when email_confirmed_at is present" do
      user = build(:user, email_confirmed_at: Time.current)
      expect(user.email_verified?).to be true
    end
  end

  describe "#verify_email" do
    it "sets email_confirmed_at and clears confirmation_token" do
      user = create(:user, email_confirmed_at: nil, confirmation_token: "token123")
      user.verify_email

      expect(user.email_confirmed_at).to be_present
      expect(user.confirmation_token).to be_nil
    end
  end

  describe "#send_confirmation_email" do
    let(:user) { create(:user) }

    it "generates a confirmation token" do
      expect(user.confirmation_token).to be_present
    end

    it "sets confirmation_sent_at" do
      expect(user.confirmation_sent_at).to be_present
    end

    it "queues ConfirmationEmailJob" do
      user = build(:user)
      expect {
        user.save
      }.to have_enqueued_job(ConfirmationEmailJob)
    end
  end

  describe "#confirmation_period_valid?" do
    it "returns false when confirmation_sent_at is nil" do
      user = build(:user, confirmation_sent_at: nil)
      expect(user.confirmation_period_valid?).to be false
    end

    it "returns true when sent less than 5 minutes ago" do
      user = build(:user, confirmation_sent_at: 2.minutes.ago)
      expect(user.confirmation_period_valid?).to be true
    end

    it "returns false when sent more than 5 minutes ago" do
      user = build(:user, confirmation_sent_at: 10.minutes.ago)
      expect(user.confirmation_period_valid?).to be false
    end
  end

  describe "magic links" do
    let(:user) { create(:user) }

    describe "#send_magic_link" do
      it "generates a magic link token" do
        user.send_magic_link
        expect(user.magic_link_token).to be_present
      end

      it "sets magic_link_expires_at to 15 minutes from now" do
        travel_to Time.current do
          user.send_magic_link
          expect(user.magic_link_expires_at).to be_within(1.second).of(15.minutes.from_now)
        end
      end

      it "queues MagicLinkJob" do
        expect {
          user.send_magic_link
        }.to have_enqueued_job(MagicLinkJob)
      end
    end

    describe "#magic_link_valid?" do
      it "returns false when token is nil" do
        user.update(magic_link_token: nil)
        expect(user.magic_link_valid?).to be false
      end

      it "returns false when expired" do
        user.update(
          magic_link_token: "token",
          magic_link_expires_at: 1.hour.ago,
          magic_link_used_at: nil
        )
        expect(user.magic_link_valid?).to be false
      end

      it "returns false when already used" do
        user.update(
          magic_link_token: "token",
          magic_link_expires_at: 10.minutes.from_now,
          magic_link_used_at: Time.current
        )
        expect(user.magic_link_valid?).to be false
      end

      it "returns true when token is valid and not expired or used" do
        user.update(
          magic_link_token: "token",
          magic_link_expires_at: 10.minutes.from_now,
          magic_link_used_at: nil
        )
        expect(user.magic_link_valid?).to be true
      end
    end

    describe "#magic_link_token_matches?" do
      it "returns false when token is blank" do
        user.update(magic_link_token: "secret")
        expect(user.magic_link_token_matches?(nil)).to be false
      end

      it "returns false when provided token doesn't match" do
        user.update(magic_link_token: "secret")
        expect(user.magic_link_token_matches?("wrong")).to be false
      end

      it "returns true when tokens match" do
        user.update(magic_link_token: "secret")
        expect(user.magic_link_token_matches?("secret")).to be true
      end

      it "uses constant-time comparison" do
        user.update(magic_link_token: "secret")
        # This tests that we're using secure_compare
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original
        user.magic_link_token_matches?("secret")
      end
    end

    describe "#consume_magic_link_token!" do
      it "marks token as used and clears it" do
        user.update(
          magic_link_token: "token",
          magic_link_expires_at: 10.minutes.from_now,
          magic_link_used_at: nil
        )

        user.consume_magic_link_token!

        expect(user.magic_link_used_at).to be_present
        expect(user.magic_link_token).to be_nil
        expect(user.magic_link_expires_at).to be_nil
      end

      it "returns false if token is invalid" do
        user.update(magic_link_token: nil)
        expect(user.consume_magic_link_token!).to be false
      end
    end
  end

  describe "roles" do
    it "defaults to user role" do
      user = create(:user)
      expect(user.user?).to be true
    end

    describe "#admin?" do
      it "returns true for admin role" do
        user = create(:user, role: :admin)
        expect(user.admin?).to be true
      end

      it "returns true for superadmin role" do
        user = create(:user, role: :superadmin)
        expect(user.admin?).to be true
      end

      it "returns true for owner role" do
        user = create(:user, role: :owner)
        expect(user.admin?).to be true
      end

      it "returns false for user role" do
        user = create(:user, role: :user)
        expect(user.admin?).to be false
      end
    end
  end

  describe "#p_id generation" do
    it "generates a unique p_id on creation" do
      user = create(:user)
      expect(user.p_id).to match(/^PWL[A-Z0-9]{10}$/)
    end

    it "generates different p_ids for different users" do
      user1 = create(:user)
      user2 = create(:user)
      expect(user1.p_id).not_to eq(user2.p_id)
    end
  end

  describe "#regen_pid" do
    it "generates a new p_id" do
      user = create(:user)
      old_pid = user.p_id

      new_pid = user.regen_pid

      expect(new_pid).not_to eq(old_pid)
      expect(user.reload.p_id).to eq(new_pid)
    end
  end
end
