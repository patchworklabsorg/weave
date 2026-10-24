# frozen_string_literal: true

require "rails_helper"

# The member's own demographics form (see DemographicsVault).
RSpec.describe "Member demographics", type: :request do
  let(:member) { create(:user, :verified, :accepted_code_of_conduct) }

  before { sign_in_via_magic_link(member) }

  it "shows an empty form with the data page link" do
    get demographics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Demographics for funder reports", "Answer every question", Weave.data_page_url,
                                     "You have not answered yet.")
    expect(response.body).not_to include("Prefer not to say", "Tick the box")
  end

  it "saves the answers sealed" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" } }

    expect(response).to redirect_to(demographics_path)
    record = DemographicRecord.find_by!(user: member)
    expect(demographics_reader.open(record.envelope)["answers"]["gender_identity"]).to eq("woman")
  end

  it "never shows the answers again, not even to the member" do
    patch demographics_path, params: { demographics: { gender_identity: "non_binary" } }

    get demographics_path

    expect(response.body).to include("You answered on")
    expect(response.body).not_to match(/value="non_binary"[^>]*checked/)
    expect(response.body).not_to match(/checked[^>]*value="non_binary"/)
  end

  it "asks again when a question has no answer" do
    patch demographics_path, params: { demographics: { gender_identity: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Pick one of the options")
    expect(DemographicRecord.where(user: member)).to be_empty
  end

  context "with a return_to from an app" do
    before do
      Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.org/auth/callback", scopes: "openid")
    end

    it "sends the member back to the app after they save" do
      get demographics_path(return_to: "https://krater.example.org/apply")
      expect(response.body).to include('value="https://krater.example.org/apply"')

      patch demographics_path, params: { demographics: { gender_identity: "man" }, return_to: "https://krater.example.org/apply" }

      expect(response).to redirect_to("https://krater.example.org/apply")
    end

    it "keeps the return_to when the save fails" do
      patch demographics_path, params: { demographics: {}, return_to: "https://krater.example.org/apply" }

      expect(response.body).to include('value="https://krater.example.org/apply"')
    end

    it "ignores a return_to on any other origin" do
      ["https://evil.example.com/apply", "http://krater.example.org/apply", "https://krater.example.org:8443/x",
       "javascript:alert(1)", "//evil.example.com", "not a url"].each do |return_to|
        patch demographics_path, params: { demographics: { gender_identity: "man" }, return_to: }

        expect(response).to redirect_to(demographics_path)
      end
    end
  end

  it "lets the member answer again, which replaces the answers" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" } }
    patch demographics_path, params: { demographics: { gender_identity: "non_binary" } }

    expect(DemographicRecord.where(user: member).count).to eq(1)
    expect(demographics_reader.open(DemographicRecord.find_by!(user: member).envelope)["answers"]["gender_identity"])
      .to eq("non_binary")
  end

  it "treats a malformed answer param as no answers, not as a server error" do
    patch demographics_path, params: { demographics: "woman" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(DemographicRecord.where(user: member)).to be_empty
  end

  it "lets the member take the answers back" do
    patch demographics_path, params: { demographics: { gender_identity: "woman" } }

    delete demographics_path

    expect(response).to redirect_to(profile_path)
    expect(DemographicRecord.where(user: member)).to be_empty
  end

  it "says so when the deployment has no public key" do
    DemographicsVault.public_key = nil

    get demographics_path
    expect(response.body).to include("not available yet")

    patch demographics_path, params: { demographics: { gender_identity: "woman" } }
    expect(DemographicRecord.count).to eq(0)
  end

  it "does not ask from the profile or during onboarding: Krater asks before the first grant" do
    get profile_path
    expect(response.body).not_to include(demographics_path)

    get slack_onboarding_path
    expect(response.body).not_to include(demographics_path)
  end

  it "keeps the answers out of the log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter("demographics" => { "gender_identity" => "woman" }))
      .to eq("demographics" => "[FILTERED]")
  end

  context "when an admin impersonates the member" do
    let(:owner) { create(:user, :owner, :verified) }

    before do
      sign_in_via_magic_link(owner)
      post impersonate_admin_user_path(member)
    end

    it "does not let the admin answer or take answers back for them" do
      patch demographics_path, params: { demographics: { gender_identity: "woman" } }
      expect(DemographicRecord.count).to eq(0)

      DemographicsVault.record(member, { "gender_identity" => "man" })
      delete demographics_path
      expect(DemographicRecord.where(user: member).count).to eq(1)
      expect(flash[:alert]).to include("impersonate")
    end
  end
end
