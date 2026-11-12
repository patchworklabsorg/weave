# frozen_string_literal: true

# == Schema Information
#
# Table name: patches
# Database name: primary
#
#  id            :bigint           not null, primary key
#  description   :text
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_patches_on_created_by_id  (created_by_id)
#  index_patches_on_slug           (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :patch do
    sequence(:slug) { |n| "patch-#{n}" }
    sequence(:name) { |n| "Patch #{n}" }
  end
end
