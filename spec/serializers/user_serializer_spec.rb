# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  acknowledged_over_13_at  :datetime
#  birthday                 :date
#  confirmation_sent_at     :datetime
#  confirmation_token       :string
#  email                    :string           not null
#  email_confirmed_at       :datetime
#  first_name               :string           not null
#  is_board                 :boolean          default(FALSE), not null
#  is_contractor            :boolean          default(FALSE), not null
#  is_staff                 :boolean          default(FALSE), not null
#  last_name                :string           not null
#  legal_first_name         :string
#  legal_last_name          :string
#  locked_at                :datetime
#  password_digest          :string           not null
#  phone_number             :string
#  pronouns                 :string
#  role                     :integer          default("user"), not null
#  session_duration_seconds :integer          default(2592000), not null
#  slack_birthday           :date
#  slack_city               :string
#  slack_coc_accepted_at    :datetime
#  slack_cost_center        :string
#  slack_country            :string
#  slack_department         :string
#  slack_display_name       :string
#  slack_division           :string
#  slack_github             :string
#  slack_invited_at         :datetime
#  slack_joined_at          :datetime
#  slack_linkedin           :string
#  slack_membership         :string           default("pending"), not null
#  slack_organization       :string
#  slack_phone              :string
#  slack_profile_image_url  :string
#  slack_profile_synced_at  :datetime
#  slack_pronouns           :string
#  slack_role_description   :text
#  slack_start_date         :date
#  slack_state              :string
#  slack_status_emoji       :string
#  slack_status_text        :string
#  slack_title              :string
#  slack_website            :string
#  status                   :enum             default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  manager_id               :bigint
#  p_id                     :string           not null
#  slack_id                 :string
#  slack_manager_id         :string
#
# Indexes
#
#  index_users_on_confirmation_token  (confirmation_token) UNIQUE
#  index_users_on_email               (email) UNIQUE
#  index_users_on_manager_id          (manager_id)
#  index_users_on_p_id                (p_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (manager_id => users.id)
#
require "rails_helper"

RSpec.describe UserSerializer do
  let(:user) do
    create(:user, first_name: "John", last_name: "Doe", legal_first_name: "Jonathan", legal_last_name: "Dorian")
  end

  it "uses the preferred name" do
    expect(described_class.render(user)).to include(first_name: "John", last_name: "Doe", full_name: "John Doe")
  end

  it "leaves the legal name out" do
    json = described_class.render(user, include_addresses: true)

    expect(json.keys.map(&:to_s)).not_to include(a_string_matching(/legal/))
    expect(json.to_json).not_to include("Jonathan", "Dorian")
  end
end
