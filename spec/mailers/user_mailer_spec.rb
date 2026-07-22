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
end
