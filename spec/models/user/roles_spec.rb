# frozen_string_literal: true

require "rails_helper"

# The old role booleans are now rows in user_roles. Every old accessor,
# scope and reader keeps working on top of the rows.
RSpec.describe User, "roles" do
  def count_queries(&block)
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  describe "the compatibility accessors" do
    {
      "identity_team" => "verifier", "identity_lead" => "identity_lead", "identity_key_holder" => "key_holder",
      "is_board" => "board", "is_staff" => "staff", "is_contractor" => "contractor"
    }.each do |column, key|
      it "reads #{column} and #{column}? from the #{key} role" do
        user = create(:user, :verified)
        RoleGrants.grant!(user, "verifier") if %w[identity_lead key_holder].include?(key)

        expect([user.public_send(column), user.public_send(:"#{column}?")]).to eq([false, false])
        RoleGrants.grant!(user, key)
        expect([user.public_send(column), user.public_send(:"#{column}?")]).to eq([true, true])
        expect(user.reload.public_send(column)).to be(true)
      end
    end

    it "keeps board?, staff? and contractor?" do
      user = create(:user, :verified, is_board: true, is_staff: true)

      expect([user.board?, user.staff?, user.contractor?]).to eq([true, true, false])
      expect(user.membership_label).to eq("Board member · Staff")
      expect(user.is_manager_or_manageable?).to be(true)
    end

    it "stages a change through a setter and grants or revokes it at the save" do
      user = build(:user, :verified, is_board: true)
      expect(user.is_board).to be(true)
      expect(UserRole.count).to eq(0)

      user.save!
      expect(user.reload.is_board).to be(true)

      user.update!(is_board: false, is_staff: "1")
      expect(user.reload).to have_attributes(is_board: false, is_staff: true)
      expect(UserRole.for_role("board").sole.revoke_reason).to eq("set through User#is_board=")
    end

    it "keeps the old validations of the identity roles" do
      user = create(:user, :verified)

      expect(user.update(identity_key_holder: true)).to be(false)
      expect(user.errors[:identity_key_holder]).to include("needs identity team membership")

      create_list(:user, VerificationSettings.max_key_holders, :key_holder)
      expect(user.update(identity_team: true, identity_key_holder: true)).to be(false)
      expect(user.errors[:identity_key_holder].first).to include("already 3 key holders")
      expect(user.reload.role_keys).to be_empty
    end

    it "drops a staged change on reload" do
      user = create(:user, :verified)
      user.is_board = true

      expect(user.reload.is_board).to be(false)
    end

    it "ignores the old boolean columns" do
      user = create(:user, :verified)
      ActiveRecord::Base.connection.execute("UPDATE users SET is_board = true, identity_team = true WHERE id = #{user.id}")

      expect(user.reload).to have_attributes(is_board: false, identity_team: false)
      expect(described_class.board_members).not_to include(user)
      expect(described_class.ignored_columns).to include(*User::LEGACY_ROLE_COLUMNS.keys)
    end
  end

  describe "the scopes" do
    it "selects by role" do
      verifier = create(:user, :identity_team)
      holder = create(:user, :key_holder)
      lead = create(:user, :identity_lead)
      board = create(:user, :verified, is_board: true)
      staff = create(:user, :verified, is_staff: true)
      contractor = create(:user, :verified, is_contractor: true)
      patch_lead = create(:user, :verified, :patch_lead)
      revoked = create(:user, :verified, is_board: true)
      RoleGrants.revoke!(revoked, "board")

      expect(described_class.identity_team).to contain_exactly(verifier, holder, lead)
      expect(described_class.identity_key_holders).to contain_exactly(holder)
      expect(described_class.identity_leads).to contain_exactly(lead)
      expect(described_class.board_members).to contain_exactly(board)
      expect(described_class.staff_members).to contain_exactly(staff)
      expect(described_class.contractors).to contain_exactly(contractor)
      expect(described_class.with_role("patch_lead", scope: "ganymede")).to contain_exactly(patch_lead)
      expect(described_class.with_role("patch_lead", scope: :any)).to contain_exactly(patch_lead)
      expect(described_class.with_role("patch_lead")).to be_empty
      expect(described_class.staff_members.or(described_class.contractors)).to contain_exactly(staff, contractor)
    end
  end

  describe "the readers that use the roles" do
    it "keeps the Thread Count vouch tiers" do
      expect(ThreadCount.voucher_tier(create(:user, :verified, is_board: true))).to eq("board")
      expect(ThreadCount.voucher_tier(create(:user, :verified, is_staff: true))).to eq("staff")
      expect(ThreadCount.voucher_tier(create(:user, :verified))).to eq("member")
    end

    it "keeps the system groups, which feed the directory API and the userinfo claims" do
      user = create(:user, :verified, is_staff: true, is_board: true)
      expect(user.groups.pluck(:slug)).to contain_exactly("staff", "board")

      RoleGrants.grant!(user, "verifier")
      user.update!(is_staff: false)
      expect(user.reload.groups.pluck(:slug)).to contain_exactly("board", "identity-team")
    end

    it "keeps the patch lead check of the Knot grants" do
      lead = create(:user, :verified, :patch_lead)

      expect(KnotGrants.patch_lead?(lead, "ganymede")).to be(true)
      expect(KnotGrants.any_patch_lead?(lead)).to be(true)
      expect(KnotGrants.patch_lead?(create(:user, :verified), "ganymede")).to be(false)
    end
  end

  describe "preloading" do
    it "reads the roles of a list of users with a fixed number of queries" do
      create_list(:user, 2, :key_holder)
      small = count_queries { described_class.identity_team.with_roles.each { |user| [user.identity_key_holder, user.identity_lead] } }
      create_list(:user, 4, :identity_lead)
      large = count_queries { described_class.identity_team.with_roles.each { |user| [user.identity_key_holder, user.identity_lead] } }

      expect(large).to eq(small)
    end

    it "reads every role of one user with one load" do
      user = create(:user, :key_holder, is_board: true, is_staff: true)
      user = described_class.find(user.id)

      queries = count_queries { [user.identity_team, user.identity_key_holder, user.is_board, user.is_staff, user.board?, user.role_keys] }

      expect(queries).to be <= 2
    end
  end
end
