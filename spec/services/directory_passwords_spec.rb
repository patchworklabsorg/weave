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
      "533" => :disabled, "701" => :disabled, "530" => :disabled,
      "773" => :must_change_password, "532" => :must_change_password
    }.each do |code, status|
      it "answers #{status} for AD data #{code}" do
        directory.add_user(user.p_id, password: "Ad-password-1", bind_error: code)

        expect(described_class.sign_in(user, "Ad-password-1")).to eq(status)
      end
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

    it "lets binds through again after the window" do
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
