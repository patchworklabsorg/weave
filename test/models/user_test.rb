# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                       :bigint           not null, primary key
#  acknowledged_over_13_at  :datetime
#  birthday                 :date
#  email                    :string           not null
#  first_name               :string           not null
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
#  slack_joined_at          :datetime
#  status                   :enum             default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  p_id                     :string           not null
#  slack_id                 :string
#
# Indexes
#
#  index_users_on_email             (email) UNIQUE
#  index_users_on_magic_link_token  (magic_link_token) UNIQUE
#  index_users_on_p_id              (p_id) UNIQUE
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
