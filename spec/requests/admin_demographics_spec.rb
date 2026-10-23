# frozen_string_literal: true

require "rails_helper"

# The admin page shows demographics aggregates only (see DemographicsReport).
RSpec.describe "Admin demographics", type: :request do
  let(:admin) { create(:user, :admin, :verified) }

  def answer(gender, first_name:)
    user = create(:user, :verified, first_name:)
    DemographicsVault.record(user, { "gender_identity" => gender }, consent: true)
  end

  it "shows the latest report with small counts hidden, and no member" do
    3.times { |index| answer("woman", first_name: "Wanda#{index}") }
    answer("man", first_name: "Marcus")
    DemographicsReport.generate!(reader: demographics_reader, run_by: "ops")
    sign_in_via_magic_link(admin)

    get admin_demographics_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Current members", "Woman", "hidden (fewer than 3", Weave.data_page_url, "by ops")
    expect(response.body).not_to include("Marcus", "Wanda")
  end

  it "states the threshold the shown report used" do
    DemographicReport.create!(generated_at: Time.current, threshold: 7,
                              results: { "active" => { "respondents" => nil, "fields" => {} } })
    sign_in_via_magic_link(admin)

    get admin_demographics_path

    expect(response.body).to include("Counts from 1 to 6 are hidden")
  end

  it "says when there is no report yet" do
    sign_in_via_magic_link(admin)

    get admin_demographics_path

    expect(response.body).to include("No report yet.", "demographics:report")
  end

  it "is not for members" do
    sign_in_via_magic_link(create(:user, :verified))

    get admin_demographics_path

    expect(response).not_to have_http_status(:ok)
  end

  it "shows nothing about one member on the admin user page" do
    member = create(:user, :verified)
    DemographicsVault.record(member, { "gender_identity" => "non_binary" }, consent: true)
    sign_in_via_magic_link(admin)

    get admin_user_path(member)

    expect(response.body).not_to include("Non-binary", "non_binary", "Demographics for funder")
  end
end
