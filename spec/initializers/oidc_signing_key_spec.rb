# frozen_string_literal: true

require "rails_helper"

RSpec.describe OidcSigningKey do
  # fetch! memoizes for the life of the process, and the JWKS endpoint has
  # almost certainly warmed it already, so each example needs a clean slate —
  # and has to hand back whatever was there for the examples that follow.
  around do |example|
    cached = described_class.instance_variable_get(:@fetch)
    described_class.instance_variable_set(:@fetch, nil)
    example.run
    described_class.instance_variable_set(:@fetch, cached)
  end

  def stub_credential(value)
    allow(Rails.application.credentials)
      .to receive(:dig).with(:openid_connect, :signing_key).and_return(value)
  end

  context "when credentials carry a signing key" do
    let(:pem) { OpenSSL::PKey::RSA.generate(2048).to_pem }

    before { stub_credential(pem) }

    it "returns it verbatim" do
      expect(described_class.fetch!).to eq(pem)
    end

    it "prefers it over the generated test key" do
      expect(described_class.fetch!).to eq(pem)
      expect(OpenSSL::PKey::RSA.new(described_class.fetch!).to_pem).to eq(pem)
    end
  end

  context "when credentials are empty" do
    before { stub_credential(nil) }

    # The lockbox.rb precedent: CI holds no credential keys at all, so the
    # suite cannot depend on one existing. Generated in memory and never
    # written anywhere, so no key material lands in the repo or on a runner.
    it "generates an ephemeral RSA key in the test environment" do
      key = OpenSSL::PKey::RSA.new(described_class.fetch!)

      expect(key).to be_private
      expect(key.n.num_bits).to eq(described_class::KEY_SIZE)
    end

    # Not an optimisation: a second call generating a second key would mean
    # JWKS publishing one key while id_tokens are signed with another.
    it "hands out the same key for the life of the process" do
      first = described_class.fetch!

      expect(described_class.fetch!).to eq(first)
    end

    # The point of the credentials-only design (#89): outside test there is no
    # fallback of any kind, so an id_token can only ever be signed by the one
    # key an operator deliberately installed.
    it "raises everywhere else rather than inventing a key" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect { described_class.fetch! }.to raise_error(/No OIDC signing key configured/)
    end

    it "explains where the key belongs when it raises" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      expect { described_class.fetch! }
        .to raise_error(/openid_connect\.signing_key/)
    end
  end

  # A blank credential entry is a likelier operator mistake than a missing one
  # (an empty YAML key), and must not be treated as a configured key.
  it "treats a blank credential as no credential" do
    stub_credential("   ")
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    expect { described_class.fetch! }.to raise_error(/No OIDC signing key configured/)
  end
end
