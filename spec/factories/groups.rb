# frozen_string_literal: true

# == Schema Information
#
# Table name: groups
# Database name: primary
#
#  id            :bigint           not null, primary key
#  deleted_at    :datetime
#  description   :text
#  kind          :string           default("manual"), not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_groups_on_created_by_id  (created_by_id)
#  index_groups_on_deleted_at     (deleted_at)
#  index_groups_on_name           (name) UNIQUE WHERE (deleted_at IS NULL)
#  index_groups_on_slug           (slug) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Group #{n}" }
    kind { "manual" }

    trait :system do
      kind { "system" }
    end
  end

  factory :group_membership, class: "Group::Membership" do
    group
    user
    source { "manual" }
  end
end
