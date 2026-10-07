# frozen_string_literal: true

# == Schema Information
#
# Table name: application_roles
# Database name: primary
#
#  id             :bigint           not null, primary key
#  description    :text
#  key            :string           not null
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  application_id :bigint           not null
#  created_by_id  :bigint
#
# Indexes
#
#  index_application_roles_on_application_id_and_key  (application_id,key) UNIQUE
#  index_application_roles_on_created_by_id           (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (application_id => oauth_applications.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
require "rails_helper"

RSpec.describe ApplicationRole do
  let(:application) { Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb") }
  let(:other_application) { Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb") }

  def role(**attributes) = described_class.new(application: application, key: "reviewer", name: "Reviewer", **attributes)

  it "accepts lowercase keys with -, _ and :" do
    %w[reviewer ganymede:member review_lead krater-admin].each do |key|
      expect(role(key: key)).to be_valid
    end
  end

  it "rejects keys with capitals, spaces or edge separators" do
    ["Reviewer", "two words", "-lead", "lead:", ""].each do |key|
      expect(role(key: key)).not_to be_valid
    end
  end

  it "keeps keys unique per app only" do
    role.save!

    expect(role).not_to be_valid
    expect(described_class.new(application: other_application, key: "reviewer", name: "Reviewer")).to be_valid
  end

  it "does not let the key change" do
    saved = role.tap(&:save!)

    expect(saved.update(key: "lead")).to be(false)
    expect(saved.reload.update(name: "Lead reviewer")).to be(true)
  end

  describe ".held_by" do
    let(:user) { create(:user, :verified) }
    let(:group) { create(:group) }
    let(:saved_role) { role.tap(&:save!) }

    it "finds roles held directly and through an active membership" do
      group_role = described_class.create!(application: application, key: "admin", name: "Admin")
      ApplicationRoleAssignment.create!(role: saved_role, assignee: user)
      ApplicationRoleAssignment.create!(role: group_role, assignee: group)
      create(:group_membership, group: group, user: user)

      expect(described_class.held_by(user)).to contain_exactly(saved_role, group_role)
    end

    it "leaves out roles of an expired membership" do
      ApplicationRoleAssignment.create!(role: saved_role, assignee: group)
      membership = create(:group_membership, group: group, user: user, expires_at: 1.hour.from_now)

      travel 2.hours do
        expect(described_class.held_by(user)).to be_empty
        expect(membership.reload).to be_expired
      end
    end
  end

  it "revokes lost access when a role is deleted" do
    saved = role.tap(&:save!)

    expect { saved.destroy! }.to have_enqueued_job(RevokeLostAppAccessJob).with(application_id: application.id)
  end

  it "revokes lost access when an assignment is removed" do
    assignment = ApplicationRoleAssignment.create!(role: role.tap(&:save!), assignee: create(:user, :verified))

    expect { assignment.destroy! }.to have_enqueued_job(RevokeLostAppAccessJob).with(application_id: application.id)
  end

  it "does not assign the same role twice" do
    user = create(:user, :verified)
    saved = role.tap(&:save!)
    ApplicationRoleAssignment.create!(role: saved, assignee: user)

    expect(ApplicationRoleAssignment.new(role: saved, assignee: user)).not_to be_valid
  end
end
