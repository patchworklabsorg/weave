# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverBreakGlassNoticesJob do
  include ActionMailer::TestHelper

  let(:member) { create(:user, :verified) }
  let(:requester) { create(:user, :identity_team) }
  let(:holders) { create_list(:user, 2, :key_holder) }
  let!(:lead) { create(:user, :identity_lead) }
  let(:decryption) do
    record = BreakGlass.request(create(:verification, :verified, user: member), by: requester, reason: "Fraud report: compare it").record
    holders.each { |holder| BreakGlass.approve(record, by: holder) }
    BreakGlass.decrypt!(record.reload, viewer: requester)
    record.decryptions.sole
  end

  def mail_to(user) = ActionMailer::Base.deliveries.select { |mail| mail.to.include?(user.email) }

  before { ActionMailer::Base.deliveries.clear }

  it "tells the key holders and the lead at once, and the member only after the window" do
    decryption
    described_class.perform_now

    expect(mail_to(holders.first).sole.subject).to include("decrypted")
    expect(mail_to(lead).sole.subject).to include("decrypted")
    expect(mail_to(member)).to be_empty

    travel(VerificationSettings.member_notice_delay + 1.minute) { described_class.perform_now }

    member_mail = mail_to(member).sole
    expect(member_mail.subject).to include(I18n.t("verification.break_glass_notice.subject"))
    expect(member_mail.body.encoded).to include(Weave.data_page_url)
    expect(decryption.notices.unsent).to be_empty
  end

  it "sends a member notice whose delay nobody signed off" do
    notice = decryption.notices.find_by!(recipient_kind: "member")
    BreakGlass.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")

    travel(VerificationSettings.member_notice_delay + 1.minute) { described_class.perform_now }

    expect(mail_to(member).size).to eq(1)
    expect(notice.reload).to be_sent
  end

  it "holds a signed-off delay, then sends the notice when the maximum runs out" do
    notice = decryption.notices.find_by!(recipient_kind: "member")
    BreakGlass.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")
    BreakGlass.sign_off_delay(notice, by: create(:user, :identity_lead))

    travel(VerificationSettings.member_notice_delay + 1.minute) { described_class.perform_now }
    expect(mail_to(member)).to be_empty

    travel(VerificationSettings.member_notice_delay + VerificationSettings.max_fraud_delay + 1.minute) { described_class.perform_now }

    expect(mail_to(member).size).to eq(1)
    expect(notice.reload).to be_sent
    expect(VerificationEvent.where(kind: "member_notice_delay_expired")).to exist
  end

  it "sends nothing twice" do
    decryption
    described_class.perform_now

    expect { described_class.perform_now }.not_to(change { ActionMailer::Base.deliveries.size })
  end
end
