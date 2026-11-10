# frozen_string_literal: true

require "rails_helper"

# Times on a page show in the viewer's zone (ViewerTimeZone). The member's
# verification page names the call time, so it shows which zone won.
RSpec.describe "Times in the viewer's time zone", type: :request do
  let(:member) { create(:user, :verified) }

  before do
    active_key_set_without_holders
    create(:verification, :call_scheduled, user: member, call_scheduled_for: Time.utc(2027, 1, 12, 20, 0))
    sign_in_via_magic_link(member)
  end

  it "uses the zone of the browser in the tz cookie" do
    cookies["tz"] = "America/Los_Angeles"

    get verification_path

    expect(response.body).to include("January 12, 2027 at 12:00 PM PST (20:00 UTC)")
  end

  it "uses the zone of the session when there is no cookie" do
    member.user_sessions.update_all(timezone: "Europe/Berlin") # rubocop:disable Rails/SkipsModelValidations

    get verification_path

    expect(response.body).to include("January 12, 2027 at 9:00 PM CET (20:00 UTC)")
  end

  it "says UTC when the cookie and the session have no zone Weave knows" do
    cookies["tz"] = "Etc/Unknown"

    get verification_path

    expect(response.body).to include("January 12, 2027 at 8:00 PM UTC")
  end

  it "does not keep the zone after the request" do
    cookies["tz"] = "Asia/Tokyo"

    get verification_path

    expect(Time.zone.name).to eq("UTC")
  end
end
