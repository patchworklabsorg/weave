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
#  locked_at                :datetime
#  magic_link_expires_at    :datetime
#  magic_link_sent_at       :datetime
#  magic_link_token         :string
#  magic_link_used_at       :datetime
#  password_digest          :string           not null
#  phone_number             :string
#  role                     :integer          default("user"), not null
#  session_duration_seconds :integer          default(2592000), not null
#  slack_birthday           :date
#  slack_city               :string
#  slack_cost_center        :string
#  slack_country            :string
#  slack_department         :string
#  slack_display_name       :string
#  slack_division           :string
#  slack_github             :string
#  slack_joined_at          :datetime
#  slack_linkedin           :string
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
#  index_users_on_magic_link_token    (magic_link_token) UNIQUE
#  index_users_on_manager_id          (manager_id)
#  index_users_on_p_id                (p_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (manager_id => users.id)
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user can have a birthday" do
    user = User.new(
      first_name: "John",
      last_name: "Doe",
      email: "john@example.com",
      password: "Password123!",
      birthday: Date.parse("1990-01-15")
    )

    assert_equal Date.parse("1990-01-15"), user.birthday
  end

  test "birthday is optional" do
    user = User.new(
      first_name: "Jane",
      last_name: "Doe",
      email: "jane@example.com",
      password: "Password123!"
    )

    assert_nil user.birthday
    assert user.valid?
  end

end
