# frozen_string_literal: true

require "rails_helper"

RSpec.describe MagicLinkMailer, type: :mailer do
  describe "login_link" do
    let(:user) { create(:user, first_name: "John", email: "john@example.com", magic_link_token: "test-token") }
    let(:mail) { described_class.login_link(user) }

    it "has correct subject" do
      expect(mail.subject).to eq("Your login link")
    end

    it "sends to the user's email" do
      expect(mail.to).to eq(["john@example.com"])
    end

    it "sends from the configured sender" do
      expect(mail.from).to eq(["idp@patchworklabs.org"])
    end

    it "greets the user by first name in the body" do
      expect(mail.body.encoded).to match("Hi John")
    end
  end
end
