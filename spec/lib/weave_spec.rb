# frozen_string_literal: true

require "rails_helper"

# Every helper takes the environment as an argument, so these pass plain hashes
# instead of mutating ENV.
RSpec.describe Weave do
  describe ".staging?" do
    it "is true only for WEAVE_ENV=staging" do
      expect(described_class.staging?("WEAVE_ENV" => "staging")).to be(true)
      expect(described_class.staging?("WEAVE_ENV" => "production")).to be(false)
      expect(described_class.staging?({})).to be(false)
    end
  end

  describe ".credentials_deployment" do
    it "names staging's credentials on staging" do
      expect(described_class.credentials_deployment("WEAVE_ENV" => "staging")).to eq("staging")
    end

    it "is nil when WEAVE_ENV is unset, keeping Rails' own resolution" do
      expect(described_class.credentials_deployment({})).to be_nil
    end
  end

  describe ".host and .url" do
    it "default to the production host" do
      expect(described_class.host({})).to eq("weave.patchworklabs.org")
      expect(described_class.url({})).to eq("https://weave.patchworklabs.org")
    end

    it "follow APP_HOST" do
      env = { "APP_HOST" => "weave-staging.patchworklabs.org" }

      expect(described_class.host(env)).to eq("weave-staging.patchworklabs.org")
      expect(described_class.url(env)).to eq("https://weave-staging.patchworklabs.org")
    end

    it "ignore a blank APP_HOST" do
      expect(described_class.host("APP_HOST" => " ")).to eq("weave.patchworklabs.org")
    end
  end

  describe ".p_id_prefix" do
    it "is SPWL on staging, so sandbox IDs can't pass for real ones" do
      expect(described_class.p_id_prefix("WEAVE_ENV" => "staging")).to eq("SPWL")
    end

    it "is PWL everywhere else" do
      expect(described_class.p_id_prefix({})).to eq("PWL")
    end
  end

  describe ".mail_allowlist" do
    let(:staging) { { "WEAVE_ENV" => "staging" } }

    it "is nil without the credential outside staging" do
      expect(described_class.mail_allowlist(credentials: {}, env: {})).to be_nil
    end

    # A missing credential must not silently turn staging into "mail everyone".
    it "is an empty list, allowing nobody, without the credential on staging" do
      expect(described_class.mail_allowlist(credentials: {}, env: staging)).to eq([])
    end

    it "trims and downcases a list" do
      credentials = { mail_allowlist: [" @PatchworkLabs.org", "Ops@Example.com ", ""] }

      expect(described_class.mail_allowlist(credentials: credentials, env: staging))
        .to eq(["@patchworklabs.org", "ops@example.com"])
    end

    it "accepts a comma-separated string" do
      credentials = { mail_allowlist: "@patchworklabs.org, ops@example.com,," }

      expect(described_class.mail_allowlist(credentials: credentials, env: {}))
        .to eq(["@patchworklabs.org", "ops@example.com"])
    end

    it "is an empty list, allowing nobody, when the credential is empty" do
      expect(described_class.mail_allowlist(credentials: { mail_allowlist: [] }, env: {})).to eq([])
    end
  end

  describe ".mail_domain, .mail_address and .mail_from" do
    it "default to the production host" do
      expect(described_class.mail_domain({})).to eq("weave.patchworklabs.org")
      expect(described_class.mail_address({})).to eq("hi@weave.patchworklabs.org")
      expect(described_class.mail_from({})).to eq("Weave <hi@weave.patchworklabs.org>")
    end

    it "follow MAIL_DOMAIN" do
      env = { "MAIL_DOMAIN" => "staging.example.org" }

      expect(described_class.mail_address(env)).to eq("hi@staging.example.org")
      expect(described_class.mail_from(env)).to eq("Weave <hi@staging.example.org>")
    end

    it "ignore a blank MAIL_DOMAIN" do
      expect(described_class.mail_domain("MAIL_DOMAIN" => " ")).to eq("weave.patchworklabs.org")
    end
  end
end
