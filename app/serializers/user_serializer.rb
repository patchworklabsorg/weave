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
class UserSerializer
  def initialize(user, options = {})
    @user = user
    @options = options
  end

  def as_json
    base_attributes.tap do |json|
      json[:addresses] = address_attributes if @options[:include_addresses]
      json[:sessions] = session_attributes if @options[:include_sessions]
    end
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  private

  def base_attributes
    {
      id: @user.id,
      p_id: @user.p_id,
      email: @user.email,
      first_name: @user.first_name,
      last_name: @user.last_name,
      phone_number: @user.phone_number,
      full_name: @user.full_name,
      initials: @user.initials,
      username: @user.username,
      role: @user.role,
      status: @user.status,
      email_verified: @user.email_verified?,
      slack_id: @user.slack_id,
      slack_member: @user.slack_member?,
      created_at: @user.created_at,
      updated_at: @user.updated_at
    }
  end

  def address_attributes
    {
      shipping: @user.shipping_address ? AddressSerializer.new(@user.shipping_address).as_json : nil,
      billing: @user.billing_address ? AddressSerializer.new(@user.billing_address).as_json : nil
    }
  end

  def session_attributes
    @user.user_sessions.recent.limit(5).map do |session|
      SessionSerializer.new(session).as_json
    end
  end

  class << self
    def render(user, options = {})
      new(user, options).as_json
    end

    def render_collection(users, options = {})
      users.map { |user| new(user, options).as_json }
    end

  end

end
