# frozen_string_literal: true

FactoryBot.define do
  factory :patch do
    sequence(:slug) { |n| "patch-#{n}" }
    sequence(:name) { |n| "Patch #{n}" }
  end
end
