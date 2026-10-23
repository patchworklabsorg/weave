# frozen_string_literal: true

require "rails_helper"

# Passkey sign-in and key custody share one WebAuthn relying party
# (config/initializers/webauthn.rb).
RSpec.describe "WebAuthn configuration" do # rubocop:disable RSpec/DescribeClass
  it "uses localhost on port 3000 in test" do
    expect(WebAuthn.configuration.rp_id).to eq("localhost")
    expect(WebAuthn.configuration.allowed_origins).to eq(["http://localhost:3000"])
  end

  it "takes the development origin from WEBAUTHN_ORIGIN, then PORT, then port 3000" do
    expect(Weave.webauthn_origin(rails_env: "development", env: { "PORT" => "5000" })).to eq("http://localhost:5000")
    expect(Weave.webauthn_origin(rails_env: "development", env: {})).to eq("http://localhost:3000")
    expect(Weave.webauthn_origin(rails_env: "development", env: { "PORT" => "5000", "WEBAUTHN_ORIGIN" => "http://localhost:3100" }))
      .to eq("http://localhost:3100")
    expect(Weave.webauthn_origin(rails_env: "test", env: { "PORT" => "5000" })).to eq("http://localhost:3000")
    expect(Weave.webauthn_origin(rails_env: "production", env: { "APP_HOST" => "weave-staging.patchworklabs.org" }))
      .to eq("https://weave-staging.patchworklabs.org")
  end

  it "gives key custody the same relying party as passkey sign-in" do
    expect(KeyCustody.relying_party).to be(WebAuthn.configuration.relying_party)
  end

  it "accepts every algorithm that a hardware key enrollment offers" do
    names = { -8 => "EdDSA", -7 => "ES256", -257 => "RS256" }
    expect(KeyCustody::Enrollment::ALGORITHMS.map { |alg| names.fetch(alg) })
      .to all(be_in(KeyCustody.relying_party.algorithms))
  end
end
