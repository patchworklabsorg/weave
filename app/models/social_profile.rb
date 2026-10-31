# frozen_string_literal: true

# == Schema Information
#
# Table name: social_profiles
# Database name: primary
#
#  id         :bigint           not null, primary key
#  provider   :string           not null
#  uid        :string           not null
#  username   :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_social_profiles_on_provider_and_uid      (provider,uid) UNIQUE
#  index_social_profiles_on_user_id_and_provider  (user_id,provider) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# An account on another site (GitHub for now) that a member linked to Weave.
#
# A member links one by signing in to the site through OmniAuth (see
# SocialProfilesController), so the link proves that the account is theirs.
# Weave keeps only the site's account id and the public handle. The access
# token from the sign-in is not stored: Weave never acts on the account.
#
# The uid is the site's stable account id. The handle can change on the site,
# so linking the same account again ("Refresh") updates it. An account can be linked to
# one member only, and each member can link one account of each site.
#
# Unlinking deletes the row, so the account can be linked again (by anyone).
# The PaperTrail version keeps the record of it.
class SocialProfile < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :social

  # Each provider is an OmniAuth strategy name, with how to show the account.
  # authorize_origin is where OmniAuth sends the member to sign in.
  PROVIDERS = {
    "github" => { name: "GitHub", icon: :github, profile_url: "https://github.com/%s", authorize_origin: "https://github.com" }
  }.freeze

  has_paper_trail

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :username, presence: true
  validates :provider, uniqueness: { scope: :user_id }

  # Providers with an OAuth client (see config/initializers/omniauth.rb). A
  # provider without one is not offered.
  def self.configured_providers
    PROVIDERS.keys & Rails.application.config.x.social_providers
  end

  def self.authorize_origins = configured_providers.map { |provider| PROVIDERS.fetch(provider)[:authorize_origin] }

  def self.provider_name(provider) = PROVIDERS.fetch(provider)[:name]

  def self.icon(provider) = PROVIDERS.fetch(provider)[:icon]

  def provider_name = self.class.provider_name(provider)

  def icon = self.class.icon(provider)

  def profile_url = format(PROVIDERS.fetch(provider)[:profile_url], ERB::Util.url_encode(username))

end
