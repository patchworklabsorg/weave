# frozen_string_literal: true

require "rails_helper"

# The permanent log: a Postgres trigger writes it, so every write path is in
# it, and the database refuses to change or delete a row.
RSpec.describe PrivilegedAttributeChange do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :verified) }

  def rows_for(person) = described_class.where(user_id: person.id).order(:id)

  def connection = ActiveRecord::Base.connection

  def summary_rows(person) = rows_for(person).map { |row| [row.attribute_name, row.old_value, row.new_value, row.operation] }

  it "logs a role grant from the user_roles trigger and a role change from the users trigger" do
    user.update!(is_board: true, role: :admin, first_name: "Changed")

    expect(summary_rows(user)).to contain_exactly(["role:board", "false", "true", "grant"], ["role", "0", "1", "update"])
    grant = rows_for(user).find(&:role_change?)
    expect(grant).to have_attributes(user_p_id: user.p_id, role_key: "board", role_scope: nil, db_user: be_present,
                                     user_role_id: UserRole.find_by!(user:).id)
    expect(grant.summary).to eq("#{user.p_id}: grant role board")
    expect(rows_for(user).find { |row| row.attribute_name == "role" }.after_value).to eq("admin (1)")
  end

  it "logs each role, with the scope of a scoped role" do
    user.update!(identity_team: true)
    user.update!(identity_key_holder: true, identity_lead: true)
    RoleGrants.grant!(user, "patch_lead", scope: "ganymede")

    expect(rows_for(user).pluck(:attribute_name))
      .to eq(%w[role:verifier role:key_holder role:identity_lead role:patch_lead[ganymede]])
    expect(rows_for(user).last).to have_attributes(role_key: "patch_lead", role_scope: "ganymede", operation: "grant")
  end

  it "logs a revoke, and the roles that the revoke takes with it" do
    user.update!(identity_team: true, identity_lead: true)
    RoleGrants.revoke!(user, "verifier", reason: "left")

    expect(summary_rows(user).last(2)).to contain_exactly(["role:identity_lead", "true", "false", "revoke"],
                                                          ["role:verifier", "true", "false", "revoke"])
  end

  it "logs nothing for other columns, for an unchanged role or for the old boolean columns" do
    user.update!(first_name: "Other", last_name: "Name")
    user.update!(is_board: false)
    connection.execute("UPDATE users SET role = role WHERE id = #{user.id}")
    connection.execute("UPDATE users SET is_board = true WHERE id = #{user.id}")

    expect(rows_for(user)).to be_empty
    expect(user.reload.is_board).to be(false)
  end

  it "catches update_all and raw SQL, which skip the callbacks" do
    User.where(id: user.id).update_all(role: User.roles[:owner]) # rubocop:disable Rails/SkipsModelValidations
    connection.execute(<<~SQL.squish)
      INSERT INTO user_roles (user_id, role_id, granted_at)
      VALUES (#{user.id}, #{Role.fetch!('verifier').id}, now())
    SQL

    expect(rows_for(user).pluck(:attribute_name)).to eq(%w[role role:verifier])
    expect(rows_for(user).pluck(:actor_id)).to all(be_nil)
  end

  it "logs an insert only when the role is above user, and each role of a new user" do
    plain = create(:user)
    board = create(:user, is_board: true, role: :admin)

    expect(rows_for(plain)).to be_empty
    expect(summary_rows(board)).to contain_exactly(["role:board", "false", "true", "grant"], ["role", nil, "1", "insert"])
  end

  it "names the actor from the session settings" do
    actor = create(:user, :owner)

    PrivilegedChangeActor.with(actor:) { user.update!(is_board: true) }
    user.update!(is_board: false)

    first, second = rows_for(user).to_a
    expect(first).to have_attributes(actor_id: actor.id, actor_label: "user #{actor.p_id}")
    expect(first.actor_name).to include(actor.full_name)
    expect(second).to have_attributes(actor_id: nil, actor_label: nil)
  end

  it "restores the earlier actor after a block" do
    PrivilegedChangeActor.set!(label: "console jasper")
    PrivilegedChangeActor.with(label: "job SomeJob") { user.update!(is_board: true) }
    user.update!(is_board: false)

    expect(rows_for(user).pluck(:actor_label)).to eq(["job SomeJob", "console jasper"])
  ensure
    PrivilegedChangeActor.clear!
  end

  it "is read-only in the app" do
    user.update!(is_board: true)

    expect { rows_for(user).first.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { rows_for(user).first.update!(new_value: "false") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "refuses UPDATE, DELETE and TRUNCATE in the database" do
    user.update!(is_board: true)
    row = rows_for(user).first

    %W[
      UPDATE\ privileged_attribute_changes\ SET\ new_value\ =\ 'false'\ WHERE\ id\ =\ #{row.id}
      DELETE\ FROM\ privileged_attribute_changes\ WHERE\ id\ =\ #{row.id}
      TRUNCATE\ privileged_attribute_changes
    ].each do |sql|
      expect { connection.transaction(requires_new: true) { connection.execute(sql) } }
        .to raise_error(ActiveRecord::StatementInvalid, /append-only/)
    end
    expect(row.reload.new_value).to eq("true")
  end

  it "keeps every row when the deletion pipeline deletes the account" do
    user.update!(is_board: true, role: :admin)
    user.update!(is_board: false, role: :user)
    p_id = user.p_id

    perform_enqueued_jobs { DeletionPipeline.run!(create(:deletion_request, :approved, user:)) }

    expect(User.exists?(user.id)).to be(false)
    rows = described_class.where(user_id: user.id)
    # role up and down, board granted and revoked.
    expect(rows.count).to eq(4)
    expect(rows.pluck(:user_p_id).uniq).to eq([p_id])
  end

  it "keeps every row through the retention and dormancy jobs" do
    user.update!(identity_team: true)

    travel(40.years) do
      DataRetentionJob.perform_now
      DormancyJob.perform_now
      PurgeVerificationDocumentsJob.perform_now
    end

    expect(rows_for(user).count).to eq(1)
  end
end
