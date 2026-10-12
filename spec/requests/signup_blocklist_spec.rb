# frozen_string_literal: true

require "rails_helper"

# Email domains on the `signup_blocked_domains` credential (see
# Weave.signup_blocked?) can't sign up. The list lives in credentials so the
# public repository does not show it, and the error does not say why.
RSpec.describe "Signup domain blocklist", type: :request do
  before { allow(Weave).to receive(:signup_blocked_domains).and_return(["blocked.example"]) }

  def sign_up(email)
    post signup_path, params: { user: { first_name: "Ada", last_name: "Lovelace", email: email } }
  end

  it "refuses a signup on a blocked domain without naming the reason" do
    expect { sign_up("ada@blocked.example") }.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(CGI.escapeHTML(User::SIGNUP_BLOCKED_MESSAGE))
    expect(response.body).not_to include("blocked.example</")
  end

  it "refuses a signup on a subdomain of a blocked domain" do
    expect { sign_up("ada@mail.blocked.example") }.not_to change(User, :count)
  end

  it "allows a domain that only ends with the same letters" do
    expect { sign_up("ada@notblocked.example") }.to change(User, :count).by(1)
  end

  it "lets an admin create an account on a blocked domain" do
    sign_in_via_magic_link(create(:user, :admin, :verified))

    expect do
      post admin_users_path, params: { user: { first_name: "Ada", last_name: "Lovelace", email: "ada@blocked.example" } }
    end.to change(User, :count).by(1)
  end

  it "does not let a user add a blocked address as a secondary email" do
    user = create(:user, :verified)

    expect(user.email_addresses.new(email: "ada@blocked.example")).not_to be_valid
  end

  it "keeps existing accounts on a blocked domain valid" do
    allow(Weave).to receive(:signup_blocked_domains).and_return([])
    user = create(:user, :verified, email: "old@blocked.example")
    allow(Weave).to receive(:signup_blocked_domains).and_return(["blocked.example"])

    expect(user.reload).to be_valid
  end

  it "does not create a user for a Slack member on a blocked domain" do
    allow(SlackService).to receive(:new).and_return(instance_double(SlackService, post_code_of_conduct: true))

    expect do
      SlackWebhookService.process_team_join("id" => "U900", "profile" => { "email" => "ada@blocked.example" })
    end.not_to change(User, :count)
  end
end
