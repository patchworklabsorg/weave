# frozen_string_literal: true

require "rails_helper"

# Per-project onboarding: a group for a sponsored project can waive the
# Patchwork code of conduct and the Patchwork Slack for its members.
RSpec.describe User do
  let(:user) { create(:user, :verified) }
  let(:project) { create(:group, name: "HackBoston", waives_code_of_conduct: true, waives_slack: true) }

  it "requires the code of conduct and Slack from people in no project" do
    expect(user.code_of_conduct_required?).to be(true)
    expect(user.slack_required?).to be(true)
    expect(user.onboarding_pending?).to be(true)
  end

  it "waives both for members of the project group" do
    create(:group_membership, group: project, user: user)

    expect(user.code_of_conduct_required?).to be(false)
    expect(user.slack_required?).to be(false)
    expect(user.onboarding_pending?).to be(false)
  end

  it "does not waive anything through an expired membership" do
    membership = create(:group_membership, group: project, user: user)
    membership.update_column(:expires_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(user.code_of_conduct_required?).to be(true)
  end

  it "still asks every member for a birthday" do
    create(:group_membership, group: project, user: user)
    user.update_column(:birthday, nil) # rubocop:disable Rails/SkipsModelValidations

    expect(user.onboarding_pending?).to be(true)
  end

  it "refuses a Slack waiver without the code of conduct waiver, because members accept it in Slack" do
    group = build(:group, waives_slack: true, waives_code_of_conduct: false)

    expect(group).not_to be_valid
    expect(group.errors[:waives_slack]).to be_present
  end

  it "rechecks app access for the members when a waiver is turned off" do
    create(:group_membership, group: project, user: user)

    expect { project.update!(waives_slack: false, waives_code_of_conduct: false) }
      .to have_enqueued_job(RevokeLostAppAccessJob).with(user_id: user.id)
  end

  it "lets project members use apps that require the code of conduct" do
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://app.example.com/cb", scopes: "profile")
    expect(AppAccess.explain(user, application).reason).to eq(:code_of_conduct)

    create(:group_membership, group: project, user: user)

    expect(AppAccess.permitted?(user, application)).to be(true)
  end

  it "keeps the age and guardian consent rules for project members" do
    minor = create(:user, :verified, :minor)
    create(:group_membership, group: project, user: minor)
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://app.example.com/cb", scopes: "profile")

    expect(AppAccess.explain(minor, application).reason).to eq(:guardian_consent)
  end
end
