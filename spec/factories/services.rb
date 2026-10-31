# frozen_string_literal: true

# == Schema Information
#
# Table name: services
# Database name: primary
#
#  id            :bigint           not null, primary key
#  description   :text
#  name          :string           not null
#  status        :string           default("active"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint           not null
#
# Indexes
#
#  index_services_on_created_by_id  (created_by_id)
#  index_services_on_name           (name) UNIQUE
#  index_services_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#
FactoryBot.define do
  # A service that calls the Weave API with a key (see Api::V1::BaseController).
  factory :service do
    sequence(:name) { |n| "Service #{n}" }
    status { "active" }
    created_by factory: %i[user admin verified]
  end

  # The raw key is in #api_key on the built record only, as in the app.
  factory :service_key, class: "Service::Key" do
    service
    name { "Primary" }
    status { "active" }
    created_by { service.created_by }
    api_key { Service::Key.generate_api_key }
  end

  factory :service_webhook, class: "Service::Webhook" do
    service
    url { "https://hooks.example.com/weave" }
    event_type { "group.member_added" }
    status { "active" }
    created_by { service.created_by }
  end
end
