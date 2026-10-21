# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveDirectory::Config do
  let(:ca_file) { FakeDirectory.ca_file }
  let(:complete) do
    {
      "AD_ENABLED"       => "true",
      "AD_BIND_DN"       => "svc-weave-ldap@patchwork.internal",
      "AD_BIND_PASSWORD" => "secret",
      "AD_CA_FILE"       => ca_file
    }
  end

  def config(env, credentials: {}) = described_class.new(env: env, credentials: credentials)

  it "is off by default" do
    expect(config({})).not_to be_enabled
    expect(config({})).not_to be_usable
  end

  it "uses the Patchwork DCs, LDAPS port and base DN by default" do
    defaults = config({})

    expect(defaults.hosts).to eq(%w[loom.patchwork.internal spindle.patchwork.internal])
    expect(defaults.port).to eq(636)
    expect(defaults.base_dn).to eq("OU=Patchwork,DC=patchwork,DC=internal")
  end

  it "is usable when enabled and complete" do
    expect(config(complete)).to be_usable
  end

  it "is not usable without a readable CA bundle" do
    expect(config(complete.merge("AD_CA_FILE" => "/nonexistent/ca.pem"))).not_to be_usable
    expect(config(complete.except("AD_CA_FILE")).missing).to include(/AD_CA_FILE/)
  end

  it "is not usable without the service account" do
    expect(config(complete.except("AD_BIND_DN"))).not_to be_usable
    expect(config(complete.except("AD_BIND_PASSWORD"))).not_to be_usable
  end

  it "reads the service account password from a secret file" do
    file = Rails.root.join("tmp/fake-ad-bind-password")
    File.write(file, "from-file\n")

    settings = config(complete.except("AD_BIND_PASSWORD").merge("AD_BIND_PASSWORD_FILE" => file.to_s))

    expect(settings.bind_password).to eq("from-file")
    expect(settings).to be_usable
  ensure
    FileUtils.rm_f(file)
  end

  it "falls back to credentials" do
    settings = config({}, credentials: { active_directory: { enabled: true, bind_dn: "svc", bind_password: "pw", ca_file: ca_file, hosts: "dc1.example, dc2.example" } })

    expect(settings).to be_usable
    expect(settings.hosts).to eq(%w[dc1.example dc2.example])
  end

  it "always verifies the peer certificate and host name against the CA bundle" do
    options = config(complete).tls_options

    expect(options[:verify_mode]).to eq(OpenSSL::SSL::VERIFY_PEER)
    expect(options[:verify_hostname]).to be(true)
    expect(options[:ca_file]).to eq(ca_file)
    expect(options[:min_version]).to eq(OpenSSL::SSL::TLS1_2_VERSION)
  end

  it "builds LDAPS connections with that TLS context and the connect timeout" do
    settings = config(complete.merge("AD_CONNECT_TIMEOUT" => "3"))
    built = []
    allow(Net::LDAP).to receive(:new) { |args| built << args }

    ActiveDirectory::Client.new(config: settings).send(:build_ldap, "loom.patchwork.internal", { method: :simple })

    expect(built.first).to include(host: "loom.patchwork.internal", port: 636, connect_timeout: 3.0)
    expect(built.first[:encryption]).to eq(method: :simple_tls, tls_options: settings.tls_options)
  end

  it "never shows the password in inspect" do
    expect(config(complete).inspect).not_to include("secret")
  end
end
