# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlags::UserLookup do
  let!(:user) { create(:user, email: "ada@example.com", slack_id: "U012AB3CD") }

  describe ".call" do
    it "finds a user by p_id in any letter case and with extra spaces" do
      expect(described_class.call(user.p_id)).to eq(user)
      expect(described_class.call("  #{user.p_id.downcase}  ")).to eq(user)
    end

    it "finds a user by public id, with the prefix in any letter case" do
      expect(described_class.call(user.public_id)).to eq(user)
      expect(described_class.call(user.public_id.sub("usr_", "USR_"))).to eq(user)
    end

    it "finds a user by primary email in any letter case" do
      expect(described_class.call(" Ada@Example.COM ")).to eq(user)
    end

    it "finds a user by an email in a name and address, or a mailto link" do
      expect(described_class.call("Ada Lovelace <ada@example.com>")).to eq(user)
      expect(described_class.call("mailto:ada@example.com")).to eq(user)
    end

    it "finds a user by a confirmed secondary email" do
      create(:email_address, :confirmed, user:, email: "ada.alt@example.com")

      expect(described_class.call("ada.alt@example.com")).to eq(user)
    end

    it "does not find a user by an unconfirmed secondary email" do
      create(:email_address, user:, email: "ada.alt@example.com")

      expect(described_class.call("ada.alt@example.com")).to be_nil
    end

    it "finds a user by Slack member id in any letter case" do
      expect(described_class.call("u012ab3cd")).to eq(user)
    end

    it "returns nil for a value that matches no user" do
      expect(described_class.call("nobody@example.com")).to be_nil
      expect(described_class.call("usr_nothing")).to be_nil
      expect(described_class.call("PWL0000000000")).to be_nil
      expect(described_class.call("   ")).to be_nil
      expect(described_class.call(nil)).to be_nil
    end
  end
end
