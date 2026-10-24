# frozen_string_literal: true

require "rails_helper"

# Waiting shares live in the database, so every web process sees them.
RSpec.describe KeyCustody::PendingShares do
  let(:share) { SecureRandom.random_bytes(33) }
  let(:holder) { create(:user, :key_holder) }
  let(:other_holder) { create(:user, :key_holder) }

  it "keeps the share, and take hands it out once" do
    described_class.put("break_glass:1:1", holder.id, share)

    expect(described_class.holder_ids("break_glass:1:1")).to eq([holder.id])
    expect(described_class.take("break_glass:1:1")).to eq(holder.id => share)
    expect(described_class.take("break_glass:1:1")).to eq({})
    expect(KeyCustodyPendingShare.count).to eq(0)
  end

  it "stores only Lockbox ciphertext, never the share bytes" do
    described_class.put("break_glass:1:1", holder.id, share)

    row = ActiveRecord::Base.connection.select_all("SELECT * FROM key_custody_pending_shares").rows.to_json
    [share.unpack1("H*"), Base64.strict_encode64(share), Base64.urlsafe_encode64(share, padding: false)].each do |value|
      expect(row).not_to include(value)
    end
  end

  it "binds a share to its request: a row moved to another request does not open" do
    described_class.put("break_glass:1:1", holder.id, share)
    KeyCustodyPendingShare.update_all(memory_key: "break_glass:2:1") # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.take("break_glass:2:1") }.to raise_error(KeyCustody::Refused, /does not belong/)
  end

  it "ignores an expired share and the sweep deletes it" do
    described_class.put("break_glass:1:1", holder.id, share, ttl: 1.minute)
    described_class.put("activate:3:new", other_holder.id, share, ttl: 10.minutes)

    travel(2.minutes) do
      expect(described_class.holder_ids("break_glass:1:1")).to be_empty
      expect(described_class.take("break_glass:1:1")).to eq({})
      expect(described_class.sweep!).to eq(1)
      expect(KeyCustodyPendingShare.pluck(:memory_key)).to eq(["activate:3:new"])
    end
  end

  it "replaces a holder's older share for the same request" do
    described_class.put("break_glass:1:1", holder.id, share)
    newer = SecureRandom.random_bytes(33)
    described_class.put("break_glass:1:1", holder.id, newer)

    expect(described_class.take("break_glass:1:1")).to eq(holder.id => newer)
  end

  it "removes the share of one holder and keeps the others" do
    described_class.put("break_glass:1:1", holder.id, share)
    described_class.put("break_glass:1:1", other_holder.id, share)

    described_class.remove("break_glass:1:1", holder.id)

    expect(described_class.holder_ids("break_glass:1:1")).to eq([other_holder.id])
  end

  it "discards every share of a request by prefix, and only those" do
    described_class.put("break_glass:1:1", holder.id, share)
    described_class.put("break_glass:1:2", other_holder.id, share)
    described_class.put("break_glass:10:1", holder.id, share)

    described_class.discard_prefix("break_glass:1:")

    expect(KeyCustodyPendingShare.pluck(:memory_key)).to eq(["break_glass:10:1"])
  end

  it "locks the rows it takes, so a second process can't take them too" do
    described_class.put("break_glass:1:1", holder.id, share)

    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
    described_class.take("break_glass:1:1")
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(statements.grep(/key_custody_pending_shares/).join).to include("FOR UPDATE")
  end

  it "keeps no PaperTrail and filters the share from inspect" do
    described_class.put("break_glass:1:1", holder.id, share)

    expect(KeyCustodyPendingShare.new).not_to respond_to(:versions)
    expect(KeyCustodyPendingShare.first.inspect).to include("[FILTERED]")
  end

  it "deletes a holder's waiting shares with the account (cascade)" do
    foreign_key = ActiveRecord::Base.connection.foreign_keys(:key_custody_pending_shares).sole

    expect(foreign_key).to have_attributes(to_table: "users", column: "holder_id")
    expect(foreign_key.on_delete).to eq(:cascade)
  end
end
