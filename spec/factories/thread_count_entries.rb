# frozen_string_literal: true

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
FactoryBot.define do
  # A Thread Count ledger entry (see ThreadCount::Entry). Defaults to a staff
  # vouch typed in by its author.
  factory :thread_count_entry, class: "ThreadCount::Entry" do
    user factory: %i[user verified]
    kind { "staff_vouch" }
    level { "staff" }
    author factory: %i[user admin verified]
    recorded_by { author }
    reason { "Ran the hack night with them and saw their work." }

    trait :moderation_case do
      kind { "moderation_case" }
      level { "minor" }
    end

    trait :external_signal do
      kind { "external_signal" }
      level { "github_student" }
    end
  end
end
