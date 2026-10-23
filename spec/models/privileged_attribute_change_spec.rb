# frozen_string_literal: true

require "rails_helper"

# The permanent log: a Postgres trigger writes it, so every write path is in
# it, and the database refuses to change or delete a row.
RSpec.describe PrivilegedAttributeChange do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :verified) }

  def rows_for(person) = described_class.where(user_id: person.id).order(:id)

  def connection = ActiveRecord::Base.connection

  it "logs one row for each changed privileged column, with the old and new value" do
    user.update!(is_board: true, role: :admin, first_name: "Changed")

    rows = rows_for(user)
    expect(rows.map { |row| [row.attribute_name, row.old_value, row.new_value, row.operation] })
      .to contain_exactly(["is_board", "false", "true", "update"], ["role", "0", "1", "update"])
    expect(rows.first).to have_attributes(user_p_id: user.p_id, db_user: be_present, changed_at: be_present)
    expect(rows.find { |row| row.attribute_name == "role" }.after_value).to eq("admin (1)")
  end

  it "logs each of the five columns" do
    user.update!(identity_team: true)
    user.update!(identity_key_holder: true, identity_lead: true)

    expect(rows_for(user).pluck(:attribute_name)).to eq(%w[identity_team identity_key_holder identity_lead])
  end

  it "logs nothing for other columns or for an unchanged value" do
    user.update!(first_name: "Other", last_name: "Name")
    user.update!(is_board: false)
    connection.execute("UPDATE users SET role = role WHERE id = #{user.id}")

    expect(rows_for(user)).to be_empty
  end

  it "catches update_column, update_all and raw SQL, which skip the callbacks" do
    user.update_column(:is_board, true) # rubocop:disable Rails/SkipsModelValidations
    User.where(id: user.id).update_all(role: User.roles[:owner]) # rubocop:disable Rails/SkipsModelValidations
    connection.execute("UPDATE users SET identity_team = true WHERE id = #{user.id}")

    expect(rows_for(user).pluck(:attribute_name)).to eq(%w[is_board role identity_team])
    expect(rows_for(user).pluck(:actor_id)).to all(be_nil)
  end

  it "logs an insert only when a flag is true or the role is above user" do
    plain = create(:user)
    board = create(:user, is_board: true, role: :admin)

    expect(rows_for(plain)).to be_empty
    expect(rows_for(board).map { |row| [row.attribute_name, row.old_value, row.new_value, row.operation] })
      .to contain_exactly(["is_board", nil, "true", "insert"], ["role", nil, "1", "insert"])
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
