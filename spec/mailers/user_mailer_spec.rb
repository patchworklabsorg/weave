# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  let(:user) { build(:user, first_name: "Ada", email: "ada@example.com") }

  describe "#welcome_email" do
    subject(:mail) { described_class.welcome_email(user) }

    it "is addressed to the user with a welcome subject" do
      expect(mail.to).to eq(["ada@example.com"])
      expect(mail.subject).to include("Welcome to Patchwork Labs")
    end

    it "greets the user by name and explains the next steps" do
      body = mail.body.encoded
      expect(body).to include("Ada")
      expect(body).to match(/Slack invite/i)
      expect(body).to match(/Code of Conduct/i)
    end
  end

  describe "#slack_email_address_added" do
    subject(:mail) { described_class.slack_email_address_added(address) }

    let(:saved_user) { create(:user, :verified, first_name: "Ada", email: "ada@example.com") }
    let(:address) { saved_user.email_addresses.create!(email: "ada.new@example.com") }

    it "goes to the primary address, not the new one" do
      expect(mail.to).to eq(["ada@example.com"])
      expect(mail.subject).to include("A new email address was added to your account")
    end

    it "names the new address and says what to do if the change was not expected" do
      body = mail.body.encoded
      expect(body).to include("ada.new@example.com")
      expect(body).to include("Slack")
      expect(body).to match(/didn't change/i)
    end
  end

  describe "#code_of_conduct_request" do
    subject(:mail) { described_class.code_of_conduct_request(user, deadline: Date.new(2026, 11, 1)) }

    it "asks the member to sign in and accept" do
      expect(mail.to).to eq(["ada@example.com"])
      expect(mail.subject).to include("Code of Conduct")
      body = mail.body.encoded
      expect(body).to include("Hi Ada,", "Sign in to Weave with ada@example.com", "/login", "November 1, 2026")
    end
  end
end
