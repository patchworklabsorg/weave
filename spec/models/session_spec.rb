# frozen_string_literal: true

# == Schema Information
#
# Table name: sessions
# Database name: primary
#
#  id         :bigint           not null, primary key
#  data       :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  session_id :string           not null
#
# Indexes
#
#  index_sessions_on_session_id  (session_id) UNIQUE
#  index_sessions_on_updated_at  (updated_at)
#
require "rails_helper"

RSpec.describe Session, type: :model do
  describe "validations" do
    # session_id is NOT NULL, so give the uniqueness matcher a persistable record.
    subject { described_class.new(session_id: SecureRandom.hex(16)) }

    it { is_expected.to validate_presence_of(:session_id) }
    it { is_expected.to validate_uniqueness_of(:session_id) }
  end

  describe "cleanup" do
    it "can find old sessions" do
      old_session = described_class.create!(
        session_id: SecureRandom.hex(16),
        data: {},
        updated_at: 2.days.ago
      )

      recent_session = described_class.create!(
        session_id: SecureRandom.hex(16),
        data: {}
      )

      old_sessions = described_class.where("updated_at < ?", 1.day.ago)
      expect(old_sessions).to include(old_session)
      expect(old_sessions).not_to include(recent_session)
    end
  end
end
