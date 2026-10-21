# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveDirectory::Client do
  let(:directory) { FakeDirectory.new }
  let(:client) { directory.client }
  let!(:account) { directory.add_user("PWL1ABCDEF12", password: "Correct-horse-1", name: "Ada Lovelace") }
  let(:entry) { client.find_employee("PWL1ABCDEF12") }

  describe "#find_employee" do
    it "finds the AD user whose employeeID is the p_id, as the service account" do
      expect(entry.dn).to eq(account.dn)
      expect(entry.employee_id).to eq("PWL1ABCDEF12")
      expect(entry.user_principal_name).to eq("ada lovelace@patchwork.internal")
      expect(directory.binds).to eq([["loom.patchwork.internal", FakeDirectory::SERVICE_DN]])
    end

    it "returns nil when no AD user has the employeeID" do
      expect(client.find_employee("PWL9999999999")).to be_nil
    end

    it "escapes the value in the filter" do
      filters = []
      allow(directory).to receive(:call).and_wrap_original do |original, *args|
        original.call(*args).tap do |connection|
          allow(connection).to receive(:search).and_wrap_original do |search, **options|
            filters << options[:filter].to_s
            search.call(**options)
          end
        end
      end

      client.find_employee("*)(cn=*")

      expect(filters.first).to include("employeeID=\\2A\\29\\28cn=\\2A")
    end

    it "refuses to guess when two AD users carry the same employeeID" do
      directory.add_user("PWL1ABCDEF12", password: "x", name: "Copy")

      expect { client.find_employee("PWL1ABCDEF12") }.to raise_error(ActiveDirectory::AmbiguousLink)
    end

    it "raises Unavailable when the service account can't bind, and does not try the next DC" do
      directory.service_password = "rotated"

      expect { client.find_employee("PWL1ABCDEF12") }.to raise_error(ActiveDirectory::Unavailable)
      expect(directory.binds.map(&:first)).to eq(["loom.patchwork.internal"])
    end
  end

  describe "#authenticate" do
    it "binds as the user's DN and returns :ok for the right password" do
      expect(client.authenticate(entry, "Correct-horse-1")).to eq(:ok)
      expect(directory.binds.last).to eq(["loom.patchwork.internal", account.dn])
    end

    it "never sends a bind for an empty password (AD would treat it as anonymous)" do
      entry
      expect { client.authenticate(entry, "") }.not_to(change { directory.binds.size })
      expect(client.authenticate(entry, "")).to eq(:invalid_credentials)
    end

    {
      "52e" => :invalid_credentials,
      "525" => :invalid_credentials,
      "530" => :restricted,
      "531" => :restricted,
      "532" => :password_expired,
      "533" => :disabled,
      "701" => :account_expired,
      "773" => :must_change_password,
      "775" => :locked
    }.each do |code, status|
      it "maps AD data #{code} to #{status}" do
        connection = instance_double(FakeDirectory::Connection, bind: false, get_operation_result: OpenStruct.new(
          code: 49, message: "Invalid Credentials",
          error_message: "80090308: LdapErr: DSID-0C09044E, comment: AcceptSecurityContext error, data #{code}, v4563"
        ))
        stub_client = described_class.new(config: directory.config, ldap_factory: ->(_host, _auth) { connection }, logger: Logger.new(nil))

        expect(stub_client.authenticate(entry, "any-password")).to eq(status)
      end
    end

    it "returns the AD answer for a wrong password from loom and does not retry on spindle" do
      expect(client.authenticate(entry, "wrong")).to eq(:invalid_credentials)
      user_binds = directory.binds.select { |_host, username| username == account.dn }
      expect(user_binds.map(&:first)).to eq(["loom.patchwork.internal"])
    end

    it "reports must-change and disabled accounts" do
      account.bind_error = "773"
      expect(client.authenticate(entry, "Correct-horse-1")).to eq(:must_change_password)

      account.bind_error = "533"
      expect(client.authenticate(entry, "Correct-horse-1")).to eq(:disabled)
    end
  end

  describe "failover" do
    it "uses spindle when loom refuses the connection" do
      directory.down_hosts << "loom.patchwork.internal"

      expect(client.authenticate(entry, "Correct-horse-1")).to eq(:ok)
      expect(directory.binds.map(&:first).uniq).to eq(["spindle.patchwork.internal"])
    end

    it "uses spindle when loom times out" do
      entry
      directory.slow_hosts << "loom.patchwork.internal"

      expect(client.authenticate(entry, "Correct-horse-1")).to eq(:ok)
      expect(directory.binds.last).to eq(["spindle.patchwork.internal", account.dn])
    end

    it "uses spindle when the TLS handshake with loom fails" do
      entry
      allow(directory).to receive(:call).and_wrap_original do |original, host, auth|
        raise OpenSSL::SSL::SSLError, "certificate verify failed" if host == "loom.patchwork.internal"

        original.call(host, auth)
      end

      expect(client.authenticate(entry, "Correct-horse-1")).to eq(:ok)
    end

    it "raises Unavailable when no DC answers" do
      directory.down_hosts.push("loom.patchwork.internal", "spindle.patchwork.internal")

      expect { client.find_employee("PWL1ABCDEF12") }.to raise_error(ActiveDirectory::Unavailable, /no domain controller answered/)
    end

    it "raises Unavailable without trying when the configuration is incomplete" do
      incomplete = directory.client("AD_BIND_DN" => "")

      expect { incomplete.find_employee("PWL1ABCDEF12") }.to raise_error(ActiveDirectory::Unavailable, /not configured/)
      expect(directory.binds).to be_empty
    end
  end

  describe "#change_password" do
    it "sends one modify that deletes the old value and adds the new one, as UTF-16LE in quotes" do
      expect(client.change_password(entry, current: "Correct-horse-1", new: "Battery-staple-2")).to eq(:ok)

      operations = directory.modifications.last[:operations]
      expect(operations.map { |operation| operation.first(2) }).to eq([[:delete, :unicodePwd], [:add, :unicodePwd]])
      expect(operations.last.last.first).to eq("\"Battery-staple-2\"".encode(Encoding::UTF_16LE).b)
      expect(account.password).to eq("Battery-staple-2")
    end

    it "reports a wrong current password (AD 00000056)" do
      expect(client.change_password(entry, current: "wrong", new: "Battery-staple-2")).to eq(:invalid_current_password)
    end

    it "reports an AD policy refusal (0000052D) as :policy_rejected" do
      directory.modify_error = {
        code: 19,
        message: "0000052D: Constraint violation - check_password_restrictions: the password does not meet the complexity criteria!\u0000"
      }

      expect(client.change_password(entry, current: "Correct-horse-1", new: "short")).to eq(:policy_rejected)
    end
  end

  describe "#reset_password" do
    it "sends a replace as the service account" do
      expect(client.reset_password(entry, "Battery-staple-2")).to eq(:ok)

      expect(directory.modifications.last[:operations].map(&:first)).to eq([:replace])
      expect(directory.binds.last.last).to eq(FakeDirectory::SERVICE_DN)
    end

    it "reports missing rights as :not_permitted" do
      directory.modify_error = { code: 50, message: "00000005: SecErr: DSID-031A11E2, problem 4003 (INSUFF_ACCESS_RIGHTS)" }

      expect(client.reset_password(entry, "Battery-staple-2")).to eq(:not_permitted)
    end

    it "reports an AD policy refusal as :policy_rejected" do
      directory.modify_error = { code: 19, message: "0000052D: Constraint violation" }

      expect(client.reset_password(entry, "x")).to eq(:policy_rejected)
    end
  end

  describe ".encode_password" do
    it "quotes the password and encodes it as UTF-16LE bytes" do
      expect(described_class.encode_password("Pä55!")).to eq("\x22\x00P\x00\xE4\x005\x005\x00!\x00\x22\x00".b)
    end
  end
end
