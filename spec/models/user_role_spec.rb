# frozen_string_literal: true

require "rails_helper"

# Role assignments are permanent: a revoke sets revoked_at once, and the
# database refuses every other change, DELETE and TRUNCATE. Triggers write
# each grant and revoke to the permanent log.
# == Schema Information
# Schema version: 20261023120000
#
# Table name: user_roles
# Database name: primary
#
#  id                              :bigint           not null, primary key
#  granted_at                      :datetime         not null
#  reason                          :text
#  revoke_reason                   :text
#  revoked_at                      :datetime
#  scope                           :string
#  created_at                      :datetime         not null
#  granted_by_id                   :bigint
#  identity_governance_proposal_id :bigint
#  revoked_by_id                   :bigint
#  role_id                         :bigint           not null
#  user_id                         :bigint
#
# Indexes
#
#  index_user_roles_active_by_role                      (role_id,scope) WHERE (revoked_at IS NULL)
#  index_user_roles_on_granted_by_id                    (granted_by_id)
#  index_user_roles_on_identity_governance_proposal_id  (identity_governance_proposal_id)
#  index_user_roles_on_revoked_by_id                    (revoked_by_id)
#  index_user_roles_on_role_id                          (role_id)
#  index_user_roles_on_user_id                          (user_id)
#  index_user_roles_one_active_assignment               (user_id, role_id, COALESCE(scope, ''::character varying)) UNIQUE WHERE (revoked_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (granted_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (identity_governance_proposal_id => identity_governance_proposals.id) ON DELETE => nullify
#  fk_rails_...  (revoked_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (role_id => roles.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
RSpec.describe UserRole do
  let(:user) { create(:user, :verified) }
  let(:actor) { create(:user, :owner, :verified) }

  delegate :connection, to: :'ActiveRecord::Base'

  def refused(sql, pattern = /user_roles/)
    expect { connection.transaction(requires_new: true) { connection.execute(sql) } }
      .to raise_error(ActiveRecord::StatementInvalid, pattern)
  end

  def log_rows = PrivilegedAttributeChange.where(user_id: user.id).order(:id)

  it "validates the scope against the role" do
    global = described_class.new(user:, role: Role.fetch!("staff"), scope: "ganymede", granted_at: Time.current)
    scoped = described_class.new(user:, role: Role.fetch!("patch_lead"), scope: "europa", granted_at: Time.current)

    expect(global).not_to be_valid
    expect(global.errors[:scope]).to include("must be empty for a global role")
    expect(scoped).not_to be_valid
    expect(scoped.errors[:scope].first).to include("ganymede")
  end

  it "allows one active assignment of a role and scope for each person" do # rubocop:disable RSpec/NoExpectationExample
    RoleGrants.grant!(user, "staff")

    refused(<<~SQL.squish, /index_user_roles_one_active_assignment/)
      INSERT INTO user_roles (user_id, role_id, granted_at) VALUES (#{user.id}, #{Role.fetch!('staff').id}, now())
    SQL
  end

  it "shows a label with the scope" do
    row = RoleGrants.grant!(user, "patch_lead", scope: "ganymede")

    expect(row.label).to eq("Patch lead (ganymede)")
    expect(row.key).to eq("patch_lead")
  end

  describe "the permanent log trigger" do
    it "logs a grant with the role, the scope and the actor of the session" do
      row = PrivilegedChangeActor.with(actor:) { RoleGrants.grant!(user, "patch_lead", scope: "ganymede") }

      expect(log_rows.sole).to have_attributes(
        operation: "grant", attribute_name: "role:patch_lead[ganymede]", role_key: "patch_lead", role_scope: "ganymede",
        user_role_id: row.id, user_p_id: user.p_id, old_value: "false", new_value: "true", actor_id: actor.id,
        actor_label: "user #{actor.p_id}"
      )
    end

    it "logs a revoke once, with the actor" do
      RoleGrants.grant!(user, "staff")
      PrivilegedChangeActor.with(label: "job SomeJob") { RoleGrants.revoke!(user, "staff", reason: "Left") }

      expect(log_rows.pluck(:operation)).to eq(%w[grant revoke])
      expect(log_rows.last).to have_attributes(old_value: "true", new_value: "false", actor_label: "job SomeJob")
    ensure
      PrivilegedChangeActor.clear!
    end

    it "logs a raw SQL grant and revoke too" do
      role_id = Role.fetch!("board").id
      connection.execute("INSERT INTO user_roles (user_id, role_id, granted_at) VALUES (#{user.id}, #{role_id}, now())")
      connection.execute("UPDATE user_roles SET revoked_at = now() WHERE user_id = #{user.id}")

      expect(log_rows.pluck(:operation, :role_key)).to eq([%w[grant board], %w[revoke board]])
    end
  end

  describe "the append-only trigger" do
    let!(:row) { RoleGrants.grant!(user, "staff", by: actor, reason: "Hired") }

    it "refuses DELETE and TRUNCATE" do
      refused("DELETE FROM user_roles WHERE id = #{row.id}", /DELETE is not allowed/)
      refused("TRUNCATE user_roles", /TRUNCATE is not allowed/)
      expect { row.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(described_class.exists?(row.id)).to be(true)
    end

    it "refuses an UPDATE of anything but the revoke fields" do
      board = Role.fetch!("board").id
      other = create(:user).id
      [
        "role_id = #{board}", "scope = 'x'", "granted_at = now() - interval '1 day'", "reason = 'Changed'",
        "user_id = #{other}", "granted_by_id = #{other}", "created_at = now() - interval '1 day'"
      ].each do |change|
        refused("UPDATE user_roles SET #{change} WHERE id = #{row.id}", /only a revoke can change a row/)
      end
      expect(row.reload).to have_attributes(reason: "Hired", user_id: user.id, granted_by_id: actor.id)
    end

    it "allows the revoke once, and refuses a second revoke or an edit of it" do
      connection.execute("UPDATE user_roles SET revoked_at = now(), revoke_reason = 'Left', revoked_by_id = #{actor.id} WHERE id = #{row.id}")

      refused("UPDATE user_roles SET revoked_at = now() + interval '1 day' WHERE id = #{row.id}", /already revoked/)
      refused("UPDATE user_roles SET revoke_reason = 'Other' WHERE id = #{row.id}", /already revoked/)
      refused("UPDATE user_roles SET revoked_at = NULL WHERE id = #{row.id}", /already revoked/)
      expect(row.reload).to have_attributes(revoke_reason: "Left", revoked_by_id: actor.id)
    end

    it "refuses revoke fields without revoked_at" do # rubocop:disable RSpec/NoExpectationExample
      refused("UPDATE user_roles SET revoke_reason = 'x' WHERE id = #{row.id}", /user_roles_revoke_fields_need_revoked_at/)
    end

    it "lets the database empty the user and actor ids when those accounts go" do
      RoleGrants.revoke!(user, "staff", by: actor, reason: "Left")

      actor.destroy!
      user.destroy!

      expect(row.reload).to have_attributes(user_id: nil, granted_by_id: nil, revoked_by_id: nil, revoke_reason: "Left")
    end
  end
end
