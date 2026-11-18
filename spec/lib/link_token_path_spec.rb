# frozen_string_literal: true

require "rails_helper"

RSpec.describe LinkTokenPath do
  let(:token) { "s3cr3t-Link_T0ken" }

  # A new route with a `:token` segment must be added to PREFIXES, or its
  # token goes to the request log.
  it "covers each route that has a token in the path" do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
                 .select { |spec| spec.include?(":token") }
                 .map { |spec| spec.sub("(.:format)", "").sub(":token", token) }

    expect(paths).not_to be_empty
    expect(paths.map { |path| described_class.redact(path) }.join(" ")).not_to include(token)
  end

  it "keeps the route and the query string" do
    expect(described_class.redact("/guardian/#{token}?step=2")).to eq("/guardian/[FILTERED]?step=2")
  end

  it "redacts a full URL" do
    expect(described_class.redact("https://weave.example/auth/magic_link/#{token}"))
      .to eq("https://weave.example/auth/magic_link/[FILTERED]")
  end

  it "leaves other paths as they are" do
    expect(described_class.redact("/guardian-consent")).to eq("/guardian-consent")
    expect(described_class.redact("/admin/guardian_consents/12")).to eq("/admin/guardian_consents/12")
    expect(described_class.redact(nil)).to eq("")
  end
end
