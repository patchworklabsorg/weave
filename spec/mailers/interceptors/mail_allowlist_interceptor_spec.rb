# frozen_string_literal: true

require "rails_helper"

RSpec.describe Interceptors::MailAllowlistInterceptor do
  let(:allowlist) { nil }
  let(:staging) { false }

  before do
    allow(Weave).to receive_messages(mail_allowlist: allowlist, staging?: staging)
  end

  def message(to: [], cc: [], bcc: [], subject: "Your login link")
    Mail.new(to: to, cc: cc, bcc: bcc, subject: subject)
  end

  def intercept(mail)
    described_class.delivering_email(mail)
    mail
  end

  context "when MAIL_ALLOWLIST is unset" do
    it "changes nothing" do
      mail = intercept(message(to: ["someone@example.com"], cc: ["other@example.org"]))

      expect(mail.to).to eq(["someone@example.com"])
      expect(mail.cc).to eq(["other@example.org"])
      expect(mail.subject).to eq("Your login link")
      expect(mail.perform_deliveries).to be(true)
    end
  end

  context "with a domain entry" do
    let(:allowlist) { ["@patchworklabs.org"] }

    it "keeps any address on that domain, ignoring case" do
      mail = intercept(message(to: ["Jasper@PatchworkLabs.org"]))

      expect(mail.to).to eq(["Jasper@PatchworkLabs.org"])
      expect(mail.perform_deliveries).to be(true)
    end

    it "does not match a lookalike domain" do
      mail = intercept(message(to: ["a@evilpatchworklabs.org", "b@patchworklabs.org.example.com"]))

      expect(mail.perform_deliveries).to be(false)
    end
  end

  context "with an exact address entry" do
    let(:allowlist) { ["tester@example.com"] }

    it "keeps only that address" do
      mail = intercept(message(to: ["tester@example.com", "other@example.com"]))

      expect(mail.to).to eq(["tester@example.com"])
    end
  end

  context "with mixed recipients across to, cc and bcc" do
    let(:allowlist) { ["@patchworklabs.org", "tester@example.com"] }

    it "removes the ones not on the list from every field and still delivers" do
      mail = intercept(message(
                         to: ["real.person@gmail.com"],
                         cc: ["tester@example.com", "stranger@example.com"],
                         bcc: ["ops@patchworklabs.org"]
                       ))

      expect(mail.to).to be_blank
      expect(mail.cc).to eq(["tester@example.com"])
      expect(mail.bcc).to eq(["ops@patchworklabs.org"])
      expect(mail.perform_deliveries).to be(true)
    end
  end

  context "when every recipient is dropped" do
    let(:allowlist) { ["@patchworklabs.org"] }

    it "cancels delivery and logs it" do
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with(/no allowed recipients left/)

      mail = intercept(message(to: ["real.person@gmail.com"]))

      expect(mail.perform_deliveries).to be(false)
    end

    it "is not delivered through Action Mailer" do
      expect { TestMailer.test_email("real.person@gmail.com").deliver_now }
        .not_to(change { ActionMailer::Base.deliveries.size })
    end
  end

  context "when on staging" do
    let(:staging) { true }

    it "prefixes the subject" do
      expect(intercept(message(to: ["a@example.com"])).subject).to eq("[staging] Your login link")
    end

    it "does not prefix twice" do
      mail = intercept(intercept(message(to: ["a@example.com"])))

      expect(mail.subject).to eq("[staging] Your login link")
    end
  end

  it "does not prefix the subject outside staging" do
    expect(intercept(message(to: ["a@example.com"])).subject).to eq("Your login link")
  end
end
