# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppAccess do
  let(:user) { create(:user, :verified) }
  let(:application) do
    Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example.com/cb", access_policy: "restricted")
  end

  def grant(grantee) = ApplicationAccessGrant.create!(application: application, grantee: grantee)

  it "lets anyone use an app that is open to everyone" do
    application.update!(access_policy: "everyone")

    decision = described_class.explain(user, application)

    expect(decision).to be_permitted
    expect(decision.to_s).to eq("Open to everyone")
  end

  it "treats an unknown policy value as restricted, so a bad value fails closed" do
    application.update_column(:access_policy, "typo") # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.permitted?(user, application)).to be(false)
  end

  it "refuses a user with no grant" do
    decision = described_class.explain(user, application)

    expect(decision).not_to be_permitted
    expect(decision.to_s).to eq("No grant for this user or their groups")
  end

  it "does not let admins in without a grant" do
    expect(described_class.permitted?(create(:user, :owner), application)).to be(false)
  end

  it "allows a direct grant" do
    grant(user)

    expect(described_class.explain(user, application).reason).to eq(:direct)
  end

  describe "app roles" do
    let(:role) { ApplicationRole.create!(application: application, key: "reviewer", name: "Reviewer") }

    it "allows a user who holds a role in the app and names the role" do
      ApplicationRoleAssignment.create!(role: role, assignee: user)

      decision = described_class.explain(user, application)

      expect(decision).to be_permitted
      expect(decision.to_s).to eq("Holds the Reviewer role")
    end

    it "allows a member of a group that holds a role" do
      group = create(:group)
      create(:group_membership, group: group, user: user)
      ApplicationRoleAssignment.create!(role: role, assignee: group)

      expect(described_class.explain(user, application).reason).to eq(:role)
    end

    it "does not count a role in another app" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb")
      other_role = ApplicationRole.create!(application: other, key: "reviewer", name: "Reviewer")
      ApplicationRoleAssignment.create!(role: other_role, assignee: user)

      expect(described_class.permitted?(user, application)).to be(false)
    end

    it "lists role keys and linked group slugs for the app, sorted" do
      admin_role = ApplicationRole.create!(application: application, key: "admin", name: "Admin")
      group = create(:group, name: "Krater Admins")
      unlinked = create(:group, name: "Payroll")
      [group, unlinked].each { |g| create(:group_membership, group: g, user: user) }
      ApplicationRoleAssignment.create!(role: admin_role, assignee: group)
      ApplicationRoleAssignment.create!(role: role, assignee: user)

      expect(described_class.role_keys(user, application)).to eq(%w[admin reviewer])
      expect(described_class.group_slugs(user, application)).to eq(["krater-admins"])
    end
  end

  it "allows a member of a granted group and names the group" do
    group = create(:group, name: "Engineering")
    create(:group_membership, group: group, user: user)
    grant(group)

    decision = described_class.explain(user, application)

    expect(decision).to be_permitted
    expect(decision.to_s).to eq("Member of Engineering")
  end

  it "stops allowing a member once the membership expires" do
    group = create(:group)
    create(:group_membership, group: group, user: user, expires_at: 1.hour.from_now)
    grant(group)

    travel 2.hours do
      expect(described_class.permitted?(user, application)).to be(false)
    end
  end

  it "stops allowing members of a group that was deleted" do
    group = create(:group)
    create(:group_membership, group: group, user: user)
    grant(group)

    group.destroy

    expect(described_class.permitted?(user, application)).to be(false)
  end

  it "does not let a grant to another app count" do
    other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb")
    ApplicationAccessGrant.create!(application: other, grantee: user)

    expect(described_class.permitted?(user, application)).to be(false)
  end

  describe ".token_usable?" do
    def token_for(owner) = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: owner&.id)

    it "passes a client_credentials token, which has no user" do
      expect(described_class.token_usable?(token_for(nil))).to be(true)
    end

    it "fails a token whose user has no access" do
      expect(described_class.token_usable?(token_for(user))).to be(false)
    end

    it "fails a token whose user can no longer sign in, even with a grant" do
      grant(user)
      user.update_columns(locked_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.token_usable?(token_for(user))).to be(false)
    end

    it "passes a token whose user has access" do
      grant(user)

      expect(described_class.token_usable?(token_for(user))).to be(true)
    end
  end

  describe "the code-of-conduct requirement" do
    before { application.update!(access_policy: "everyone") }
    after { Flipper.remove(described_class::CODE_OF_CONDUCT_FLAG) }

    it "is off while the flag does not exist" do
      expect(described_class.explain(user, application)).to be_permitted
    end

    it "is off while the flag is disabled" do
      Flipper.disable(described_class::CODE_OF_CONDUCT_FLAG)

      expect(described_class.explain(user, application)).to be_permitted
    end

    context "when the flag is on" do
      before { Flipper.enable(described_class::CODE_OF_CONDUCT_FLAG) }

      it "refuses a user who has not accepted, even for an open app" do
        decision = described_class.explain(user, application)

        expect(decision).not_to be_permitted
        expect(decision.to_s).to eq("Has not accepted the Code of Conduct")
      end

      it "refuses a user who has not accepted, even with a grant" do
        application.update!(access_policy: "restricted")
        grant(user)

        expect(described_class.permitted?(user, application)).to be(false)
      end

      it "lets a user who accepted use the app" do
        user.update!(slack_coc_accepted_at: 1.day.ago)

        expect(described_class.permitted?(user, application)).to be(true)
      end

      it "stops the user's tokens" do
        token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id)

        expect(described_class.token_usable?(token)).to be(false)
      end
    end
  end
end
