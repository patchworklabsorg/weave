# frozen_string_literal: true

require "rails_helper"

RSpec.describe BreakGlassBoardReportJob do
  include ActiveJob::TestHelper

  it "emails the report for the previous month to each board member" do
    board = create(:user, :verified, is_board: true)
    create(:user, :verified)

    travel_to(Time.zone.local(2026, 11, 1, 9)) do
      expect { described_class.perform_now }
        .to have_enqueued_mail(BreakGlassMailer, :board_report).with(board, "2026-10-01").once
    end
  end

  it "lists each decryption and each delayed notice in the mail" do
    member = create(:user, :verified)
    requester = create(:user, :identity_team)
    record = BreakGlass.request(create(:verification, :verified, user: member), by: requester, reason: "Fraud report: compare it").record
    BreakGlass.approve(record, by: create(:user, :key_holder))
    BreakGlass.approve(record, by: create(:user, :key_holder))
    BreakGlass.decrypt!(record.reload, viewer: requester)
    BreakGlass.delay_member_notice(BreakGlassNotice.find_by!(recipient_kind: "member"), by: requester, reason: "Active fraud case 12")

    mail = BreakGlassMailer.board_report(create(:user, :verified, is_board: true), Date.current.beginning_of_month.iso8601)

    expect(mail.body.encoded).to include("Decryptions: 1", record.public_id, "Fraud report: compare it", "Active fraud case 12")
  end
end
