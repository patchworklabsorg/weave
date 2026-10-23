# frozen_string_literal: true

require "rails_helper"

# The member's own demographics form (see DemographicsVault).
RSpec.describe "Member demographics", type: :request do
  let(:member) { create(:user, :verified, :accepted_code_of_conduct) }

  before { sign_in_via_magic_link(member) }

  it "shows an empty form with the data page link" do
    get demographics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demographics for funder reports", "Prefer not to say", Weave.data_page_url,
                                     "You have not answered yet.")
  end

  it "saves the answers sealed and sends the member back to the profile" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" }, consent: "1" }

    expect(response).to redirect_to(profile_path)
    record = DemographicRecord.find_by!(user: member)
    expect(demographics_reader.open(record.envelope)["answers"]["gender_identity"]).to eq("woman")
  end

  it "never shows the answers again, not even to the member" do
    patch demographics_path, params: { demographics: { gender_identity: "non_binary" }, consent: "1" }

    get demographics_path

    expect(response.body).to include("You answered on")
    expect(response.body).not_to match(/value="non_binary"[^>]*checked/)
    expect(response.body).not_to match(/checked[^>]*value="non_binary"/)
  end

  it "asks again when the member does not agree" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Tick the box to agree")
    expect(DemographicRecord.where(user: member)).to be_empty
  end

  it "lets the member answer again, which replaces the answers" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" }, consent: "1" }
    patch demographics_path, params: { demographics: { gender_identity: "prefer_not_to_say" }, consent: "1" }

    expect(DemographicRecord.where(user: member).count).to eq(1)
    expect(demographics_reader.open(DemographicRecord.find_by!(user: member).envelope)["answers"]["gender_identity"])
      .to eq("prefer_not_to_say")
  end

  it "treats a malformed answer param as no answers, not as an error" do
    patch demographics_path, params: { demographics: "woman", consent: "1" }

    expect(response).to redirect_to(profile_path)
    expect(demographics_reader.open(DemographicRecord.find_by!(user: member).envelope)["answers"])
      .to include("gender_identity" => nil)
  end

  it "lets the member take the answers back" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" }, consent: "1" }

    delete demographics_path

    expect(response).to redirect_to(profile_path)
    expect(DemographicRecord.where(user: member)).to be_empty
  end

  it "says so when the deployment has no public key" do
    DemographicsVault.public_key = nil

    get demographics_path
    expect(response.body).to include("not available yet")

    patch demographics_path, params: { demographics: { gender_identity: "woman" }, consent: "1" }
    expect(DemographicRecord.count).to eq(0)
  end

  it "invites the member from the profile, without blocking anything" do
    get profile_path

    expect(response.body).to include("Help us report to our funders (optional)", demographics_path)
  end

  it "invites the member during onboarding, but not before the birthday step" do
    get slack_onboarding_path
    expect(response.body).to include("Help us report to our funders (optional)")

    member.update_columns(birthday: nil) # rubocop:disable Rails/SkipsModelValidations
    get slack_onboarding_path
    expect(response.body).not_to include("Help us report to our funders")
  end

  it "keeps the answers out of the log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter("demographics" => { "gender_identity" => "woman" }, "consent" => "1"))
      .to eq("demographics" => "[FILTERED]", "consent" => "1")
  end

  context "when an admin impersonates the member" do
    let(:owner) { create(:user, :owner, :verified) }

    before do
      sign_in_via_magic_link(owner)
      post impersonate_admin_user_path(member)
    end

    it "does not let the admin answer or take answers back for them" do
      patch demographics_path, params: { demographics: { gender_identity: "woman" }, consent: "1" }
      expect(DemographicRecord.count).to eq(0)

      DemographicsVault.record(member, { "gender_identity" => "man" }, consent: true)
      delete demographics_path
      expect(DemographicRecord.where(user: member).count).to eq(1)
      expect(flash[:alert]).to include("impersonate")
    end
  end
end
