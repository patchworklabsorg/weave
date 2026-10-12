# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuardianConsentSignals do
  let(:user) { create(:user, :verified, :minor, first_name: "Ada", last_name: "Lovelace") }
  let(:never) { instance_double(Random, rand: 0.99) }
  let(:always) { instance_double(Random, rand: 0.0) }

  def granted(**attrs)
    create(:guardian_consent, :granted, user:, sent_at: 2.days.ago, granted_at: 1.day.ago, **attrs)
  end

  it "flags a consent from a browser the member signed in with" do
    user.user_sessions.create!(session_token: SecureRandom.hex, fingerprint: "fp-123", expiration_at: 1.day.from_now)

    expect(described_class.for(granted(granted_fingerprint: "fp-123"), random: never)).to eq(["same_device"])
  end

  it "flags a consent given within minutes of the request" do
    consent = granted(sent_at: 2.minutes.ago, granted_at: 1.minute.ago)

    expect(described_class.for(consent, random: never)).to eq(["quick_grant"])
  end

  it "flags a guardian with the member's own name, in any case or spacing" do
    expect(described_class.for(granted(signed_name: "ada  LOVELACE"), random: never)).to eq(["member_name"])
  end

  it "does not flag a guardian who only shares the family name" do
    expect(described_class.for(granted(guardian_name: "Anne Lovelace", signed_name: "Anne Lovelace"), random: never)).to eq([])
  end

  it "picks some clean consents for a spot check" do
    expect(described_class.for(granted, random: always)).to eq(["spot_check"])
  end

  it "does not add a spot check when there is already a flag" do
    expect(described_class.for(granted(signed_name: "Ada Lovelace"), random: always)).to eq(["member_name"])
  end
end
