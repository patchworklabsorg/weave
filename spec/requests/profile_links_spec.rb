# frozen_string_literal: true

require "rails_helper"

# The Slack profile fields (website, GitHub, LinkedIn) are free text that a
# member types into Slack. The profile page links only http and https
# values; anything else is shown as text.
RSpec.describe "Profile links", type: :request do
  let(:user) { create(:user, :verified, slack_id: "U0001") }

  before { sign_in_via_magic_link(user) }

  it "links an https URL" do
    user.update!(slack_website: "https://example.com/me")

    get profile_path

    expect(response.body).to include('href="https://example.com/me"')
    expect(response.body).to include('rel="noopener noreferrer"')
  end

  it "does not link a javascript: value" do
    user.update!(slack_github: "javascript:alert(1)")

    get profile_path

    expect(response.body).not_to include("href=\"javascript:")
    expect(response.body).to include("GitHub")
  end

  it "does not link a value with no host" do
    user.update!(slack_linkedin: "not a url")

    get profile_path

    expect(response.body).not_to include('href="not a url"')
  end
end
