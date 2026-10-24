# frozen_string_literal: true

require "rails_helper"

# A pass has no time limit. Only a trigger (a birthday change, a legal name
# change or a blacklist review) ends it (see VerificationFlow.require_reverification).
RSpec.describe VerificationFlow, "re-verification" do # rubocop:disable RSpec/DescribeMethod, RSpec/SpecFilePathFormat
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified, legal_first_name: "Erika", legal_last_name: "Mustermann") }
  let!(:pass) { create(:verification, :verified, user: member) }

  # ID checks open only after the key ceremony (VerificationFlow.submission_blocker).
  before { active_key_set_without_holders }

  def image = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png")

  it "has no time limit: a pass still stands many years later" do
    travel 20.years do
      expect(member.reload.verification_status).to eq("verified")
      expect(described_class.submission_blocker(member)).to eq(:verified)
    end
  end

  it "has no expiry value in config and no expiry column" do
    keys = VerificationSettings.config.to_h.deep_stringify_keys.to_s
    expect(keys).not_to match(/valid_for|verification_expir|reverif.*(days|years|months)/)
    expect(Verification.column_names.grep(/expire/)).to be_empty
  end

  it "ends the pass when the birthday changes, records the reason and tells the member" do
    expect { member.update!(birthday: member.birthday - 1.day) }
      .to have_enqueued_mail(VerificationMailer, :status_changed).with(pass)

    expect(pass.reload).to have_attributes(status: "verified", reverification_reason: "birthday_changed")
    expect(pass.reverification_required_at).to be_present
    expect(member.reload.verification_status).to eq("needs_submission")
    expect(member).not_to be_identity_verified
    expect(pass.events.find_by!(kind: "reverification_required").data).to eq("reason" => "birthday_changed")
  end

  it "ends the pass when the legal name changes" do
    member.update!(legal_last_name: "Musterfrau")

    expect(pass.reload.reverification_reason).to eq("legal_name_changed")
    expect(member.reload.verification_status).to eq("needs_submission")
  end

  it "ends the pass when a legal name is set for the first time" do
    other = create(:user, :verified)
    other_pass = create(:verification, :verified, user: other)

    other.update!(legal_first_name: "Jane")

    expect(other_pass.reload.reverification_reason).to eq("legal_name_changed")
  end

  it "ends the pass after a blacklist review" do
    expect(described_class.require_reverification(member, reason: "blacklist_review")).to be(true)

    expect(pass.reload.reverification_reason).to eq("blacklist_review")
  end

  it "does not end a pass for other profile changes" do
    member.update!(first_name: "Riki")

    expect(pass.reload.reverification_required_at).to be_nil
    expect(member.reload.verification_status).to eq("verified")
  end

  it "does nothing when the member has no standing pass" do
    other = create(:user, :verified)
    create(:verification, :failed, user: other)

    expect(described_class.require_reverification(other, reason: "birthday_changed")).to be(false)
    expect(described_class.require_reverification(create(:user), reason: "birthday_changed")).to be(false)
  end

  it "records one trigger only" do
    described_class.require_reverification(member, reason: "blacklist_review")

    expect(described_class.require_reverification(member, reason: "birthday_changed")).to be(false)
    expect(pass.reload.reverification_reason).to eq("blacklist_review")
  end

  it "refuses an unknown reason, so a time-based reason can't be added by accident" do
    expect { described_class.require_reverification(member, reason: "expired") }.to raise_error(ArgumentError)
  end

  it "lets the member submit a new attempt for a new call" do
    described_class.require_reverification(member, reason: "legal_name_changed")

    expect(described_class.submission_blocker(member.reload)).to be_nil
    result = described_class.submit(member, document: image, document_type: "passport")
    expect(result).to be_success
    expect(result.verification.previous_attempt).to eq(pass)
    expect(member.reload.verification_status).to eq("pending")
  end

  it "sends the member an email with the reason" do
    described_class.require_reverification(member, reason: "birthday_changed")

    mail = VerificationMailer.status_changed(pass.reload)
    expect(mail.subject).to include(I18n.t("verification.mailer.reverification_required.subject"))
    expect(mail.text_part.body.to_s).to include(I18n.t("verification.reverification_reasons.birthday_changed"))
  end
end
