# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestMailer, type: :mailer do
  describe "test_email" do
    let(:mail) { described_class.test_email("ops@example.com") }

    it "sends to the given recipient" do
      expect(mail.to).to eq(["ops@example.com"])
    end

    it "sends from the configured sender" do
      expect(mail.from).to eq(["hi@weave.patchworklabs.org"])
    end

    # The whole point of this email is to report the SMTP configuration back to
    # whoever triggered it, so the addresses in the body must be read off the
    # message rather than hard-coded — otherwise a sender change silently makes
    # the diagnostic lie. This guards both rendered formats.
    it "reports the real sender and reply-to in the body" do
      expect(mail.body.encoded).to include("hi@weave.patchworklabs.org")
      expect(mail.body.encoded).not_to include("idp@patchworklabs.org")
      expect(mail.body.encoded).not_to include("no-reply@patchworklabs.org")
    end
  end
end
