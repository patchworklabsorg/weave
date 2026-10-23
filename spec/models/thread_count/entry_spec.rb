# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: thread_count_entries
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  evidence_type           :string
#  evidence_url_ciphertext :text
#  kind                    :string           not null
#  level                   :string
#  project_ref             :string
#  reason_ciphertext       :text
#  created_at              :datetime         not null
#  author_id               :bigint
#  evidence_id             :bigint
#  recorded_by_id          :bigint
#  reverses_id             :bigint
#  service_id              :bigint
#  user_id                 :bigint           not null
#
# Indexes
#
#  index_thread_count_entries_on_author_id         (author_id)
#  index_thread_count_entries_on_evidence          (evidence_type,evidence_id)
#  index_thread_count_entries_on_project_event     (service_id,project_ref,kind) UNIQUE WHERE (project_ref IS NOT NULL)
#  index_thread_count_entries_on_recorded_by_id    (recorded_by_id)
#  index_thread_count_entries_on_reverses_id       (reverses_id) UNIQUE
#  index_thread_count_entries_on_service_id        (service_id)
#  index_thread_count_entries_on_user_id           (user_id)
#  index_thread_count_entries_on_user_id_and_kind  (user_id,kind)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => users.id) ON DELETE => nullify
#  fk_rails_...  (recorded_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (reverses_id => thread_count_entries.id) ON DELETE => cascade
#  fk_rails_...  (service_id => services.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe ThreadCount::Entry do
  it "is valid from the factory" do
    expect(build(:thread_count_entry)).to be_valid
  end

  it "uses a tce_ public ID" do
    expect(create(:thread_count_entry).public_id).to start_with("tce_")
  end

  it "encrypts the reason and the evidence link" do
    entry = create(:thread_count_entry, reason: "Secret reason", evidence_url: "https://example.org/case/1")
    row = described_class.connection.select_one("SELECT reason_ciphertext, evidence_url_ciphertext FROM thread_count_entries WHERE id = #{entry.id}")

    expect(row.values.join).not_to include("Secret reason", "example.org")
    expect(described_class.find(entry.id)).to have_attributes(reason: "Secret reason", evidence_url: "https://example.org/case/1")
  end

  describe "append-only" do
    it "can't be changed after it is saved" do
      entry = create(:thread_count_entry)

      expect { entry.update!(reason: "Changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "can't be destroyed" do
      entry = create(:thread_count_entry)

      expect { entry.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "validations" do
    it "needs a written reason for a manual entry" do
      entry = build(:thread_count_entry, reason: "  ")

      expect(entry).not_to be_valid
      expect(entry.errors[:reason]).to include("can't be blank")
    end

    it "does not need a reason for a service's project event" do
      entry = build(:thread_count_entry, kind: "project_approved", level: nil, author: nil, recorded_by: nil,
                                         service: create(:service), project_ref: "p-1", reason: nil)

      expect(entry).to be_valid
    end

    it "rejects an unknown kind" do
      expect(build(:thread_count_entry, kind: "bribe", level: nil)).not_to be_valid
    end

    it "needs a configured level for a staff vouch, a moderation case and an external signal" do
      expect(build(:thread_count_entry, level: nil)).not_to be_valid
      expect(build(:thread_count_entry, :moderation_case, level: "catastrophic")).not_to be_valid
      expect(build(:thread_count_entry, :external_signal, level: "github_student")).to be_valid
    end

    it "refuses a level on a kind without levels" do
      expect(build(:thread_count_entry, kind: "board_vouch", level: "staff")).not_to be_valid
    end

    it "accepts only an http or https evidence link" do
      expect(build(:thread_count_entry, evidence_url: "javascript:alert(1)")).not_to be_valid
      expect(build(:thread_count_entry, evidence_url: "https://krater.example.org/projects/1")).to be_valid
    end

    it "links a reversal to the entry it cancels, and nothing else does" do
      expect(build(:thread_count_entry, kind: "reversal", level: nil)).not_to be_valid
      expect(build(:thread_count_entry, reverses: create(:thread_count_entry))).not_to be_valid
    end

    it "can link evidence to another record" do
      consent = create(:guardian_consent)
      entry = create(:thread_count_entry, evidence: consent)

      expect(described_class.find(entry.id).evidence).to eq(consent)
    end
  end

  describe "when accounts are deleted" do
    it "goes with the member's account" do
      entry = create(:thread_count_entry)

      entry.user.destroy!

      expect(described_class.exists?(entry.id)).to be(false)
    end

    it "stays when the author's account is deleted, without the author" do
      entry = create(:thread_count_entry)

      entry.author.destroy!

      expect(described_class.find(entry.id)).to have_attributes(author_id: nil, recorded_by_id: nil)
    end
  end
end
