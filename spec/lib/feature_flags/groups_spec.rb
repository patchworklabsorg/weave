# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlags::Groups do
  let(:feature) { Flipper[:spec_flag] }

  before { stub_const("FeatureFlags::FLAGS", { spec_flag: "A flag for specs" }) }

  # Flipper gives a group block a Flipper::Types::Actor wrapper, so each example
  # goes through Flipper.enabled? to check the real path, not the matcher alone.
  describe "group gates" do
    it "matches every user for the users group" do
      feature.enable_group(:users)

      expect(feature.enabled?(create(:user))).to be(true)
    end

    it "matches an admin, a superadmin, and an owner for the admins group" do
      feature.enable_group(:admins)

      expect(feature.enabled?(create(:user, :admin))).to be(true)
      expect(feature.enabled?(create(:user, :superadmin))).to be(true)
      expect(feature.enabled?(create(:user, :owner))).to be(true)
      expect(feature.enabled?(create(:user))).to be(false)
    end

    it "matches a superadmin and an owner for the superadmins group" do
      feature.enable_group(:superadmins)

      expect(feature.enabled?(create(:user, :superadmin))).to be(true)
      expect(feature.enabled?(create(:user, :owner))).to be(true)
      expect(feature.enabled?(create(:user, :admin))).to be(false)
    end

    it "matches only an owner for the owners group" do
      feature.enable_group(:owners)

      expect(feature.enabled?(create(:user, :owner))).to be(true)
      expect(feature.enabled?(create(:user, :superadmin))).to be(false)
    end

    it "does not match a user when no group is enabled" do
      expect(feature.enabled?(create(:user, :owner))).to be(false)
    end
  end

  describe ".user_for" do
    it "returns the user that a Flipper actor holds, or a user passed bare" do
      user = create(:user)

      expect(described_class.user_for(Flipper::Types::Actor.new(user))).to eq(user)
      expect(described_class.user_for(user)).to eq(user)
    end

    it "returns nil for an actor that is not a user" do
      expect(described_class.user_for(Flipper::Types::Actor.new(Flipper::Actor.new("Thing;1")))).to be_nil
    end
  end

  it "does not match an actor that is not a user" do
    expect(described_class.match?(:users, Flipper::Types::Actor.new(Flipper::Actor.new("Thing;1")))).to be(false)
  end
end
