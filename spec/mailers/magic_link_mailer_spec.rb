# frozen_string_literal: true

require "rails_helper"

RSpec.describe MagicLinkMailer, type: :mailer do
  describe "login_link" do
    let(:user) { create(:user, :verified, first_name: "John", email: "john@example.com") }
    let(:mail) { described_class.login_link(user, "test-token") }

    it "has correct subject" do
      expect(mail.subject).to eq("Your login link")
    end

    it "sends to the user's email" do
      expect(mail.to).to eq(["john@example.com"])
    end

    it "sends from the configured sender" do
      expect(mail.from).to eq(["hi@weave.patchworklabs.org"])
    end

    it "greets the user by first name in the body" do
      expect(mail.body.encoded).to match("Hi John")
    end

    # Anyone can sign up with any address, so an unconfirmed account's name
    # is whatever the person who signed up typed.
    it "leaves the name out for an unconfirmed address" do
      unconfirmed = create(:user, :unverified, first_name: "Your account is suspended")

      body = described_class.login_link(unconfirmed, "test-token").body.encoded

      expect(body).to include("Hi,")
      expect(body).not_to include("suspended")
    end
  end
end
