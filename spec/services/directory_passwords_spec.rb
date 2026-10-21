# frozen_string_literal: true

require "rails_helper"

RSpec.describe DirectoryPasswords do
  let(:user) { create(:user, :verified) }
  let(:directory) { FakeDirectory.new }

  context "when AD is off" do
    it "leaves every user on Weave's own passwords and never calls AD" do
      expect(described_class.sign_in(user, "SecurePassword123!")).to eq(:not_directory)
      expect(described_class.directory_user?(user)).to be(false)
      expect(described_class.reset(user, "New-password-1")).to eq(:not_directory)
    end
  end

  context "when AD is on" do
    before { use_fake_directory(directory) }

    it "returns :not_directory for a user with no AD account" do
      expect(described_class.sign_in(user, "SecurePassword123!")).to eq(:not_directory)
      expect(user.reload.directory_linked_at).to be_nil
    end

    it "links the user and makes the old Weave password useless" do
      directory.add_user(user.p_id, password: "Ad-password-1")

      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:authenticated)

      user.reload
      expect(user.directory_linked_at).to be_present
      expect(user.authenticate("SecurePassword123!")).to be(false)
    end

    it "never saves the AD password in Weave" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      described_class.sign_in(user, "Ad-password-1")
      described_class.reset(user, "Reset-password-2")

      expect(user.reload.authenticate("Ad-password-1")).to be(false)
      expect(user.authenticate("Reset-password-2")).to be(false)
    end

    {
      "533" => :invalid, "701" => :invalid, "530" => :invalid, "531" => :invalid,
      "773" => :must_change_password, "532" => :must_change_password
    }.each do |code, status|
      it "answers #{status} for AD data #{code}" do
        directory.add_user(user.p_id, password: "Ad-password-1", bind_error: code)

        expect(described_class.sign_in(user, "Ad-password-1")).to eq(status)
      end
    end

    it "counts answers that need the right password (a disabled account) toward the limit" do
      directory.add_user(user.p_id, password: "Ad-password-1", bind_error: "533")
      described_class::MAX_FAILURES.times { described_class.sign_in(user, "Ad-password-1") }

      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:throttled)
    end

    it "reserves each attempt before the bind, so more than the limit never reach AD" do
      directory.add_user(user.p_id, password: "Ad-password-1")

      results = Array.new(described_class::MAX_FAILURES + 3) { described_class.sign_in(user, "wrong") }

      user_binds = directory.binds.count { |_host, username| username == directory.account(user.p_id).dn }
      expect(user_binds).to eq(described_class::MAX_FAILURES)
      expect(results.last).to eq(:throttled)
    end

    it "starts the window again at each attempt sent to AD (a sliding window)" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      (described_class::MAX_FAILURES - 1).times { described_class.sign_in(user, "wrong") }

      travel(10.minutes)
      described_class.sign_in(user, "wrong")
      travel(10.minutes)
      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:throttled)

      travel(6.minutes)
      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:authenticated)
    end

    it "refuses an AD object other than the pinned one, even with the same employeeID" do
      original = directory.add_user(user.p_id, password: "Ad-password-1")
      described_class.sign_in(user, "Ad-password-1")
      directory.accounts.delete(original)
      directory.add_user(user.p_id, password: "Attacker-1", name: "Impostor")

      expect(described_class.sign_in(user.reload, "Attacker-1")).to eq(:unlinked)
      expect(described_class.reset(user, "Attacker-2")).to eq(:unlinked)
    end

    it "does not link an admin automatically" do
      admin = create(:user, :admin, :verified)
      directory.add_user(admin.p_id, password: "Attacker-1")

      expect(described_class.sign_in(admin, "Attacker-1")).to eq(:not_directory)
      expect(described_class.link(admin)).to be(false)
      expect(admin.reload.directory_linked_at).to be_nil
    end

    it "links an admin when an operator asks" do
      admin = create(:user, :admin, :verified)
      account = directory.add_user(admin.p_id, password: "Admin-ad-1")

      expect(described_class.link(admin, explicit: true)).to be(true)
      expect(admin.reload.directory_object_guid).to eq(account.object_guid.unpack1("H*"))
      expect(described_class.sign_in(admin, "Admin-ad-1")).to eq(:authenticated)
    end

    it "fails closed in production when the attempt store is not shared" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rack::Attack.cache).to receive(:store).and_return(ActiveSupport::Cache::MemoryStore.new)
      directory.add_user(user.p_id, password: "Ad-password-1")

      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:unavailable)
    end

    it "answers :locked for a locked AD account (775)" do
      directory.add_user(user.p_id, password: "Ad-password-1", bind_error: "775")

      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:locked)
    end

    it "stops binding after #{described_class::MAX_FAILURES} failures, whatever the IP" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      described_class::MAX_FAILURES.times { expect(described_class.sign_in(user, "wrong")).to eq(:invalid) }

      binds_before = directory.binds.size
      expect(described_class.sign_in(user, "Ad-password-1")).to eq(:throttled)
      expect(directory.binds.size).to eq(binds_before)
    end

    it "lets binds through again after a quiet window" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      described_class::MAX_FAILURES.times { described_class.sign_in(user, "wrong") }

      travel(described_class::FAILURE_WINDOW + 1.minute) do
        expect(described_class.sign_in(user, "Ad-password-1")).to eq(:authenticated)
      end
    end

    it "fails closed when no DC answers" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      directory.down_hosts.push("loom.patchwork.internal", "spindle.patchwork.internal")

      expect(described_class.sign_in(user, "SecurePassword123!")).to eq(:unavailable)
    end

    it "fails closed when two AD accounts claim the user" do
      directory.add_user(user.p_id, password: "a", name: "One")
      directory.add_user(user.p_id, password: "b", name: "Two")

      expect(described_class.sign_in(user, "a")).to eq(:unavailable)
    end

    it "answers :unlinked when a linked user's AD account is gone" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      described_class.sign_in(user, "Ad-password-1")
      directory.accounts.clear

      expect(described_class.sign_in(user.reload, "SecurePassword123!")).to eq(:unlinked)
    end

    it "changes the password in AD and counts a wrong current password as a failure" do
      directory.add_user(user.p_id, password: "Ad-password-1")

      expect(described_class.change(user, current: "wrong", new: "New-password-2")).to eq(:invalid_current_password)
      expect(described_class.change(user, current: "Ad-password-1", new: "New-password-2")).to eq(:ok)
      expect(directory.account(user.p_id).password).to eq("New-password-2")
    end
  end

  context "when AD is on but not configured" do
    before { use_fake_directory(directory, env: { "AD_CA_FILE" => "/missing.pem" }) }

    it "fails closed for password sign-in" do
      expect(described_class.sign_in(user, "SecurePassword123!")).to eq(:unavailable)
    end
  end
end
