# frozen_string_literal: true

require "rails_helper"

# Signing in while an OAuth authorization is pending ends in a redirect to the
# client's redirect_uri once consent already exists, and Chrome/Safari apply CSP
# form-action to that whole redirect chain. The sign-in pages must therefore allow
# the pending client's registered origin -- and nothing else, and only while an
# authorization is actually pending.
RSpec.describe "form-action on the sign-in pages", type: :request do
  let(:application) do
    Doorkeeper::Application.create!(
      name: "Krater",
      redirect_uri: "https://krater.example.org/auth/callback",
      scopes: "openid profile email",
      confidential: true
    )
  end
  let(:other_application) do
    Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.net/cb", scopes: "openid")
  end

  def form_action(response)
    response.headers["Content-Security-Policy"].to_s.split(";").map(&:strip)
            .find { |directive| directive.start_with?("form-action ") }
  end

  def start_authorization
    get oauth_authorization_path, params: {
      client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code",
      scope: "openid", code_challenge: "x" * 43, code_challenge_method: "S256"
    }
  end

  it "allows only the pending client's registered origin during an OAuth sign-in" do
    other_application
    start_authorization

    get "/oauth/login", params: { client_id: application.uid }

    expect(form_action(response)).to eq("form-action 'self' https://krater.example.org")
  end

  it "applies to the magic-link confirmation page too" do
    user = create(:user, :verified)
    start_authorization
    token = User::MagicLink.issue!(user).token

    get "/auth/magic_link/#{token}"

    expect(form_action(response)).to eq("form-action 'self' https://krater.example.org")
  end

  it "stays 'self' when no OAuth authorization is pending" do
    get "/login"

    expect(form_action(response)).to eq("form-action 'self'")
  end

  it "ignores a client_id param that doesn't match a pending authorization" do
    get "/oauth/login", params: { client_id: other_application.uid }

    expect(form_action(response)).to eq("form-action 'self'")
  end
end
