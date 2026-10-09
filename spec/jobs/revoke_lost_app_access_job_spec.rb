# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeLostAppAccessJob do
  let(:user) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:group) { create(:group) }
  let(:application) do
    Doorkeeper::Application.create!(name: "Wiki", redirect_uri: "https://wiki.example.com/cb", access_policy: "restricted")
  end
  let(:open_app) { Doorkeeper::Application.create!(name: "Open", redirect_uri: "https://open.example.com/cb") }

  def token_for(app, owner = user) = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: owner.id)

  def code_for(app)
    Doorkeeper::AccessGrant.create!(application: app, resource_owner_id: user.id, redirect_uri: app.redirect_uri,
                                    expires_in: 600, scopes: "profile")
  end

  before do
    create(:group_membership, group: group, user: user)
    ApplicationAccessGrant.create!(application: application, grantee: group)
  end

  it "revokes tokens and codes for an app the user lost, and only that app" do
    lost_token = token_for(application)
    lost_code = code_for(application)
    kept_token = token_for(open_app)
    Group::Membership.where(user: user).delete_all

    described_class.perform_now(user_id: user.id)

    expect(lost_token.reload).to be_revoked
    expect(lost_code.reload).to be_revoked
    expect(kept_token.reload).not_to be_revoked
  end

  it "leaves tokens alone while the user still has access" do
    token = token_for(application)

    described_class.perform_now(user_id: user.id)

    expect(token.reload).not_to be_revoked
  end

  it "checks every user of an app when given the app" do
    other = create(:user, :verified, :accepted_code_of_conduct)
    ApplicationAccessGrant.create!(application: application, grantee: other)
    kept = token_for(application, other)
    lost = token_for(application)
    Group::Membership.where(user: user).delete_all

    described_class.perform_now(application_id: application.id)

    expect(lost.reload).to be_revoked
    expect(kept.reload).not_to be_revoked
  end

  it "needs a user or an app" do
    expect { described_class.perform_now }.to raise_error(ArgumentError)
  end

  describe "triggers" do
    include ActiveJob::TestHelper

    it "runs when a membership is removed" do
      membership = Group::Membership.find_by!(user: user)

      expect { membership.destroy! }.to have_enqueued_job(described_class).with(user_id: user.id)
    end

    it "runs for each member when a group is deleted" do
      expect { group.destroy }.to have_enqueued_job(described_class).with(user_id: user.id)
    end

    it "runs when a grant is removed" do
      grant = ApplicationAccessGrant.find_by!(application: application)

      expect { grant.destroy! }.to have_enqueued_job(described_class).with(application_id: application.id)
    end

    it "revokes end to end when an expired membership is removed" do
      membership = Group::Membership.find_by!(user: user)
      membership.update!(expires_at: 1.hour.from_now)
      token = token_for(application)

      travel 2.hours do
        perform_enqueued_jobs { ExpireGroupMembershipsJob.perform_now }

        expect(token.reload).to be_revoked
      end
    end
  end
end
