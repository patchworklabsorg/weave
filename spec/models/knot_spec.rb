# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: knots
# Database name: primary
#
#  id          :bigint           not null, primary key
#  blacklisted :boolean          default(FALSE), not null
#  user_id     :bigint
#
# Indexes
#
#  index_knots_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
RSpec.describe Knot do
  it "carries exactly two pieces of state: the flag (here) and the grants (ProgramGrant)" do
    expect(described_class.column_names).to contain_exactly("id", "user_id", "blacklisted")
    expect(ProgramGrant.column_names).to contain_exactly("id", "knot_id", "program", "granted_at")
  end

  it "holds no reason, history or name: no timestamps and no paper trail" do
    expect(described_class.column_names.grep(/reason|_at\z|name|note/)).to be_empty
    expect(described_class).not_to respond_to(:paper_trail_options)
    expect(KnotHash.column_names).to contain_exactly("id", "knot_id", "kind", "digest")
  end

  it "keys one Knot to one live member" do
    user = create(:user)
    create(:knot, user:)

    expect { create(:knot, user:) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "lets a strong digest belong to one Knot only, and a soft digest to many" do
    digest = "a" * 64
    create(:knot_hash, kind: "soft", digest:)
    create(:knot_hash, kind: "soft", digest:)
    create(:knot_hash, kind: "document", digest:)

    expect { create(:knot_hash, kind: "document", digest:) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "accepts only hex digests" do
    expect(build(:knot_hash, digest: "C01X00T47")).not_to be_valid
  end

  it "reads the verification audit record from the newest decided attempt" do
    knot = create(:knot)
    older = create(:verification, :verified, user: knot.user, knot:, decided_at: 2.years.ago)
    newer = create(:verification, :verified, user: knot.user, knot:, decided_at: 1.day.ago)

    expect(knot.audit_verification).to eq(newer)
    expect(older.fraud_hold?).to be(false)
  end

  it "puts the attempts of a blacklisted Knot under the fraud-evidence hold" do
    knot = create(:knot, :blacklisted)
    held = create(:verification, :verified, user: knot.user, knot:)
    create(:verification, :verified)

    expect(Verification.under_fraud_hold).to contain_exactly(held)
    expect(held.fraud_hold?).to be(true)
  end

  it "drops a waiting change request when its audit record is destroyed, so the retention job is not blocked" do
    key = ActiveRecord::Base.connection.foreign_keys(:knot_change_requests).find { |fk| fk.to_table == "verifications" }

    expect(key.on_delete).to eq(:cascade)
  end
end
