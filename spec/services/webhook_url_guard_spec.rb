# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookUrlGuard do
  def resolves(host, *addresses)
    allow(Resolv).to receive(:getaddresses).with(host).and_return(addresses)
  end

  it "returns the URI and the address to connect to for a public host" do
    resolves("hooks.example.com", "93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946")

    uri, address = described_class.check!("https://hooks.example.com/weave")

    expect(uri.hostname).to eq("hooks.example.com")
    expect(address).to eq("93.184.216.34")
  end

  {
    "loopback"                    => "127.0.0.1",
    "private"                     => "10.1.2.3",
    "private (172.16/12)"         => "172.20.0.5",
    "private (192.168/16)"        => "192.168.1.1",
    "link-local (cloud metadata)" => "169.254.169.254",
    "carrier-grade NAT"           => "100.64.0.1",
    "unspecified"                 => "0.0.0.0",
    "IPv6 loopback"               => "::1",
    "IPv6 unique local"           => "fd00::1",
    "IPv6 link-local"             => "fe80::1",
    "IPv4-mapped IPv6 loopback"   => "::ffff:127.0.0.1"
  }.each do |kind, address|
    it "blocks a host that resolves to a #{kind} address" do
      resolves("hooks.example.com", address)

      expect { described_class.check!("https://hooks.example.com/") }
        .to raise_error(WebhookUrlGuard::Blocked, /blocked address/)
    end
  end

  it "blocks a host when any one of its addresses is private" do
    resolves("hooks.example.com", "93.184.216.34", "10.0.0.1")

    expect { described_class.check!("https://hooks.example.com/") }.to raise_error(WebhookUrlGuard::Blocked)
  end

  it "checks an IP address in the URL without DNS" do
    expect { described_class.check!("https://169.254.169.254/latest/meta-data") }.to raise_error(WebhookUrlGuard::Blocked)
    expect { described_class.check!("https://[::1]/") }.to raise_error(WebhookUrlGuard::Blocked)
  end

  it "blocks a host that does not resolve" do
    resolves("nowhere.example.com")

    expect { described_class.check!("https://nowhere.example.com/") }.to raise_error(WebhookUrlGuard::Blocked, /does not resolve/)
  end

  it "blocks a URL with a user name or password, or another scheme" do
    expect { described_class.check!("https://user:pass@hooks.example.com/") }.to raise_error(WebhookUrlGuard::Blocked)
    expect { described_class.check!("ftp://hooks.example.com/") }.to raise_error(WebhookUrlGuard::Blocked)
  end

  context "when in production" do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    it "accepts https only" do
      resolves("hooks.example.com", "93.184.216.34")

      expect { described_class.check!("http://hooks.example.com/") }.to raise_error(WebhookUrlGuard::Blocked, /https/)
      expect { described_class.check!("https://hooks.example.com/") }.not_to raise_error
    end
  end

  context "when in development" do
    before { allow(Rails.env).to receive(:development?).and_return(true) }

    it "allows loopback, so a receiver can run on localhost" do
      resolves("localhost", "127.0.0.1")

      expect(described_class.check!("http://localhost:4000/hook").last).to eq("127.0.0.1")
    end
  end
end
