# frozen_string_literal: true

require "rails_helper"

# DNS is stubbed through EmailDeliverability.lookup, so nothing here uses the
# network.
RSpec.describe EmailDeliverability do
  let(:mx) { Resolv::DNS::Resource::IN::MX }
  let(:a) { Resolv::DNS::Resource::IN::A }
  let(:aaaa) { Resolv::DNS::Resource::IN::AAAA }

  def stub_dns(records)
    allow(described_class).to receive(:lookup) { |_domain, type| records.fetch(type, []) }
  end

  def mx_record(exchange)
    mx.new(10, Resolv::DNS::Name.create(exchange))
  end

  it "accepts a domain with an MX record" do
    stub_dns(mx => [mx_record("mail.example.net")])

    expect(described_class.deliverable?("ada@patchworklabs.org")).to be(true)
  end

  # example.com, example.net and example.org publish "0 ." (RFC 7505).
  it "refuses a domain with a null MX" do
    stub_dns(mx => [mx_record("")], a => [a.new("93.184.215.14")])

    expect(described_class.deliverable?("ada@example.com")).to be(false)
  end

  it "accepts a domain without MX that has an address record" do
    stub_dns(a => [], aaaa => [aaaa.new("2001:db8::1")])

    expect(described_class.deliverable?("ada@host.example.net")).to be(true)
  end

  it "refuses a domain without MX or address records, such as one under .test" do
    stub_dns({})

    expect(described_class.deliverable?("ada@foo.test")).to be(false)
  end

  it "accepts the address when DNS does not answer" do
    allow(described_class).to receive(:lookup).and_return(nil)

    expect(described_class.deliverable?("ada@slow.example")).to be(true)
  end

  it "turns a resolver error into no answer" do
    allow(Resolv::DNS).to receive(:open).and_raise(Resolv::ResolvError, "DNS resolv timeout")

    expect(described_class.lookup("slow.example", mx)).to be_nil
  end

  describe "on signup" do
    before do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(described_class).to receive(:deliverable?) { |email| !email.end_with?("@example.com") }
    end

    it "refuses an address that can't receive email" do
      user = build(:user, email: "ada@example.com")

      expect(user).not_to be_valid
      expect(user.errors[:email]).to include(User::UNDELIVERABLE_MESSAGE)
    end

    it "refuses an undeliverable secondary address" do
      user = create(:user, email: "ada@patchworklabs.org")

      expect(user.email_addresses.new(email: "ada@example.com")).not_to be_valid
    end

    it "does not check existing accounts again" do
      allow(described_class).to receive(:enabled?).and_return(false)
      user = create(:user, email: "old@example.com")
      allow(described_class).to receive(:enabled?).and_return(true)

      expect(user.reload).to be_valid
    end
  end
end
