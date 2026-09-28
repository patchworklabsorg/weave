# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "revoking OAuth access when the account can no longer sign in" do
    let(:user) { create(:user, :verified) }
    let(:other_user) { create(:user, :verified) }
    let(:application) do
      Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example.com/cb", scopes: "profile")
    end

    def issue_token(owner)
      Doorkeeper::AccessToken.create!(application: application, resource_owner_id: owner.id, scopes: "profile",
                                      expires_in: 2.hours, use_refresh_token: true)
    end

    def issue_grant(owner)
      Doorkeeper::AccessGrant.create!(application: application, resource_owner_id: owner.id, scopes: "profile",
                                      expires_in: 10.minutes, redirect_uri: application.redirect_uri,
                                      code_challenge: "x" * 43, code_challenge_method: "S256")
    end

    {
      "lock!"       => ->(user) { user.lock! },
      "suspend!"    => ->(user) { user.suspend! },
      "deactivate!" => ->(user) { user.deactivate! }
    }.each do |action, change|
      it "revokes every token and unredeemed code on #{action}" do
        token = issue_token(user)
        grant = issue_grant(user)

        change.call(user)

        expect(token.reload).to be_revoked
        expect(grant.reload).to be_revoked
      end
    end

    it "leaves other users' tokens alone" do
      mine = issue_token(user)
      theirs = issue_token(other_user)

      user.lock!

      expect(mine.reload).to be_revoked
      expect(theirs.reload).not_to be_revoked
    end

    it "doesn't revoke anything on an unrelated update" do
      token = issue_token(user)

      user.update!(first_name: "Grace")

      expect(token.reload).not_to be_revoked
    end

    it "doesn't revoke anything when a user is unlocked or reactivated" do
      user.suspend!
      token = issue_token(user)

      user.reactivate!

      expect(token.reload).not_to be_revoked
    end
  end

  describe "#can_authenticate?" do
    it "is true for an active, unlocked account" do
      expect(build(:user)).to be_can_authenticate
    end

    it "is false once locked" do
      expect(build(:user, locked_at: Time.current)).not_to be_can_authenticate
    end

    it "is false for suspended and deactivated accounts" do
      expect(build(:user, status: "suspended")).not_to be_can_authenticate
      expect(build(:user, status: "deactivated")).not_to be_can_authenticate
    end
  end
end
