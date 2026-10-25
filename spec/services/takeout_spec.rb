# frozen_string_literal: true

require "rails_helper"

RSpec.describe Takeout do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :verified, first_name: "Ada", pronouns: "she/her") }

  it "exports every exportable category of the registry, and only those" do
    data = described_class.build(user)

    expect(data["categories"].keys).to eq(DataCategories.exportable.map(&:key))
    expect(data["not_included"].keys).to contain_exactly("raw_id_images", "demographics", "knot")
    expect(data["data_page"]).to eq(Weave.data_page_url)
  end

  it "holds the member's data in each category" do
    create(:guardian_consent, :granted, user:)
    create(:verification, :verified, user:)
    create(:grant_disbursement, user:)
    create(:program_participation, user:, funder: "plain_funder", program: "ganymede", year: 2025)
    create(:program_participation, :funder_required, user:, year: 2026)

    categories = described_class.build(user)["categories"]

    expect(categories["account_profile"]["data"]["profile"]).to include("first_name" => "Ada", "pronouns" => "she/her")
    expect(categories["guardian_contact"]["data"].sole).to include("guardian_name" => "Grace Hopper", "status" => "granted")
    expect(categories["verification_audit"]["data"].sole).to include("status" => "verified", "document_type" => "passport")
    expect(categories["financial"]["data"].sole).to include("amount_cents" => 50_000, "payee_name" => "Ada Lovelace")
    expect(categories["participation"]["data"]).to eq([{ "program" => "ganymede", "year" => 2025, "outcome" => "granted" }])
    expect(categories["funder_records"]["data"]).to eq([{ "program" => "ganymede", "year" => 2026, "outcome" => "granted" }])
  end

  it "lists the member's passkeys without their keys" do
    passkey = register_passkey(user, nickname: "Work laptop")

    data = described_class.build(user)["categories"]["account_profile"]["data"]

    expect(data["passkeys"]).to eq([{ "nickname" => "Work laptop", "created_at" => passkey.created_at.iso8601,
                                      "last_used_at" => nil
}])
    expect(data.to_json).not_to include(passkey.public_key, passkey.external_id)
  end

  it "lists the member's social profiles" do
    profile = user.social_profiles.create!(provider: "github", uid: "583231", username: "octocat")

    data = described_class.build(user)["categories"]["account_profile"]["data"]

    expected = { "provider" => "github", "id" => "583231", "username" => "octocat", "linked_at" => profile.created_at.iso8601 }
    expect(data["social_profiles"]).to eq([expected])
  end

  it "never holds demographics or Thread Count" do
    DemographicsVault.record(user, { "gender_identity" => "woman" })
    create(:thread_count_entry, user:, kind: "board_vouch", level: nil, reason: "SECRET-REASON")

    json = described_class.build(user).to_json

    expect(json).not_to include("woman", "gender_identity", "thread_count", "envelope", "SECRET-REASON")
  end

  it "builds the file in a job, encrypts it and emails the member" do
    result = described_class.request!(user)
    expect(result).to be_success

    perform_enqueued_jobs(only: BuildTakeoutJob)

    takeout = result.request.reload
    expect(takeout).to be_downloadable
    expect(takeout.expires_at).to be_within(1.minute).of(DataRetention.takeout_download_window.from_now)
    expect(JSON.parse(takeout.archive.download)["weave_id"]).to eq(user.p_id)
    expect(enqueued_jobs.map { |job| job["arguments"].first }).to include("DataHandlingMailer")
  end

  it "allows one export at a time and not more often than the cooldown" do
    expect(described_class.request!(user)).to be_success
    expect(described_class.request!(user).errors[:base]).to eq(I18n.t("data_handling.takeout.errors.pending"))

    user.takeout_requests.update_all(status: "ready") # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.request!(user).errors[:base]).to eq(I18n.t("data_handling.takeout.errors.cooldown"))
  end
end
