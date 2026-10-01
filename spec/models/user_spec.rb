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
require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    # Provide a fully valid record so shoulda's uniqueness matcher can persist
    # the "existing" record it compares against. The matcher saves that record
    # with `validate: false`, which skips the before_validation p_id generation,
    # so a valid p_id must be supplied here (first_name/last_name are NOT NULL).
    subject { build(:user, p_id: "PWL0ABCDEF123") }

    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

    it "validates email format" do
      user = build(:user, email: "invalid-email")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("does not appear to be a valid email address")
    end

    it "validates password complexity" do
      user = build(:user, password: "weak", password_confirmation: "weak")
      expect(user).not_to be_valid
    end

    it "allows a blank phone number" do
      user = build(:user, phone_number: "")
      expect(user).to be_valid
    end

    it "accepts a US phone number with area code" do
      user = build(:user, phone_number: "(802) 555-0123")
      expect(user).to be_valid
    end

    it "accepts an international phone number with country code" do
      user = build(:user, phone_number: "+44 20 7946 0958")
      expect(user).to be_valid
    end

    it "rejects a phone number without an area code" do
      user = build(:user, phone_number: "555-0123")
      expect(user).not_to be_valid
      expect(user.errors[:phone_number]).to include("is not a valid phone number (include your area code)")
    end

    it "rejects a non-numeric phone number" do
      user = build(:user, phone_number: "not a phone")
      expect(user).not_to be_valid
    end
  end

  describe "phone number normalization" do
    it "normalizes US numbers to E.164 on save" do
      user = create(:user, phone_number: "(802) 555-0123")
      expect(user.reload.phone_number).to eq("+18025550123")
    end

    it "keeps international numbers in E.164" do
      user = create(:user, phone_number: "+44 20 7946 0958")
      expect(user.reload.phone_number).to eq("+442079460958")
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:visits).class_name("Ahoy::Visit") }
    it { is_expected.to have_many(:user_sessions).class_name("User::Session") }
    it { is_expected.to have_many(:addresses) }
    it { is_expected.to have_one(:shipping_address) }
    it { is_expected.to have_one(:billing_address) }
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

  describe "#legal_name?" do
    it "is false when no legal name is set" do
      user = build(:user, legal_first_name: nil, legal_last_name: nil)
      expect(user.legal_name?).to be(false)
    end

    it "is true when any legal name part is set" do
      user = build(:user, legal_first_name: "Jonathan", legal_last_name: nil)
      expect(user.legal_name?).to be(true)
    end

    it "is false when legal name fields are blank strings" do
      user = build(:user, legal_first_name: "  ", legal_last_name: "")
      expect(user.legal_name?).to be(false)
    end
  end

  describe "#legal_full_name" do
    it "falls back to the preferred full name when no legal name is set" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.legal_full_name).to eq("John Doe")
    end

    it "returns the legal name when set" do
      user = build(:user, first_name: "John", last_name: "Doe",
                          legal_first_name: "Jonathan", legal_last_name: "Dorian")
      expect(user.legal_full_name).to eq("Jonathan Dorian")
    end

    it "fills missing legal name parts from the preferred name" do
      user = build(:user, first_name: "John", last_name: "Doe", legal_first_name: "Jonathan")
      expect(user.legal_full_name).to eq("Jonathan Doe")
    end
  end

  describe "legal name length" do
    it "allows up to 100 characters" do
      user = build(:user, legal_first_name: "a" * 100, legal_last_name: "b" * 100)
      expect(user).to be_valid
    end

    it "rejects more than 100 characters" do
      user = build(:user, legal_first_name: "a" * 101, legal_last_name: "b" * 101)
      expect(user).not_to be_valid
      expect(user.errors).to include(:legal_first_name, :legal_last_name)
    end
  end

  describe "legal name normalization" do
    it "strips whitespace and stores blank values as nil" do
      user = create(:user, legal_first_name: " Jonathan ", legal_last_name: "   ")
      expect(user.legal_first_name).to eq("Jonathan")
      expect(user.legal_last_name).to be_nil
    end
  end

  describe "#initials" do
    it "returns first letter of first and last name" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.initials).to eq("JD")
    end

    it "handles nil names safely" do
      user = described_class.new(first_name: nil, last_name: nil)
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
      it "issues a magic link for the user" do
        expect { user.send_magic_link }.to change { user.magic_links.count }.by(1)
      end

      it "expires the link 15 minutes out" do
        travel_to Time.current do
          user.send_magic_link
          expect(user.magic_links.last.expires_at).to be_within(1.second).of(15.minutes.from_now)
        end
      end

      it "queues MagicLinkJob" do
        expect {
          user.send_magic_link
        }.to have_enqueued_job(MagicLinkJob)
      end

      it "records the IP that asked for it" do
        user.send_magic_link(requested_ip: "203.0.113.7")

        expect(user.magic_links.last.requested_ip).to eq("203.0.113.7")
      end

      # The single-column scheme this replaced meant a second request killed the
      # first link, so anyone who double-submitted the form — or asked again
      # because the first mail was slow — hit "invalid or expired" on a link that
      # was minutes old.
      it "leaves an earlier unused link working" do
        user.send_magic_link
        first = user.magic_links.last

        user.send_magic_link

        expect(first.reload).to be_live
        expect(user.magic_links.live.count).to eq(2)
      end
    end

    # A magic link only ever reaches the address on the account, so following
    # one proves the same thing the confirmation email is asking for. Imported
    # accounts have no confirmation behind them, and requiring a second email
    # on top of the one they just used kept them out of the app entirely.
    describe "#confirm_email_from_magic_link!" do
      it "confirms the email address it was delivered to" do
        user.update!(email_confirmed_at: nil, confirmation_token: "pending")

        user.confirm_email_from_magic_link!

        expect(user.reload).to be_email_verified
        expect(user.confirmation_token).to be_nil
      end

      it "leaves an existing confirmation timestamp alone" do
        confirmed_at = 3.days.ago
        user.update!(email_confirmed_at: confirmed_at)

        user.confirm_email_from_magic_link!

        expect(user.reload.email_confirmed_at).to be_within(1.second).of(confirmed_at)
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

    # Generation and validation have to agree. On a persisted record the
    # `on: :create` callback no longer fires, so this validates the value that
    # was actually stored.
    it "generates a p_id that satisfies its own validation" do
      expect(create(:user)).to be_valid
    end
  end

  # p_id is the OIDC `sub`. A relying party allowlisting on it compares the
  # string exactly, so a lowercase variant of a real p_id must not be storable —
  # it would be a second spelling of one identity that no consumer matches.
  describe "p_id format" do
    it "accepts the uppercase hex form generate_p_id produces" do
      expect(build(:user, p_id: "PWL0ABCDEF123")).to be_valid
    end

    it "rejects lowercase hex" do
      user = build(:user, p_id: "PWL0abcdef123")

      expect(user).not_to be_valid
      expect(user.errors[:p_id]).to include("PWL ID failed format validation")
    end

    it "rejects mixed case" do
      expect(build(:user, p_id: "PWL0AbCdEf123")).not_to be_valid
    end

    it "rejects a non-hex character in the hex run" do
      expect(build(:user, p_id: "PWL0ABCDEFG12")).not_to be_valid
    end

    it "rejects a non-digit immediately after the prefix" do
      expect(build(:user, p_id: "PWLA0BCDEF123")).not_to be_valid
    end

    it "rejects a staging ID outside staging" do
      expect(build(:user, p_id: "SPWL0ABCDEF123")).not_to be_valid
    end

    context "when on staging" do
      before { allow(Weave).to receive(:p_id_prefix).and_return("SPWL") }

      it "generates SPWL IDs that pass validation" do
        user = create(:user)

        expect(user.p_id).to match(/\ASPWL\d[A-F0-9]{9}\z/)
        expect(user).to be_valid
      end

      it "rejects a production PWL ID" do
        expect(build(:user, p_id: "PWL0ABCDEF123")).not_to be_valid
      end
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
