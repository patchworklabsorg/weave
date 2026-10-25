# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe SocialProfile do
  let(:user) { create(:user, :verified) }

  it "links one account of each site per member" do
    user.social_profiles.create!(provider: "github", uid: "1", username: "first")

    second = user.social_profiles.build(provider: "github", uid: "2", username: "second")

    expect(second).not_to be_valid
    expect(second.errors[:provider]).to be_present
  end

  it "links each account to one member only" do
    user.social_profiles.create!(provider: "github", uid: "1", username: "octocat")

    taken = create(:user, :verified).social_profiles.build(provider: "github", uid: "1", username: "octocat")

    expect(taken).not_to be_valid
    expect(taken.errors[:uid]).to be_present
  end

  it "refuses a provider that Weave does not support" do
    expect(user.social_profiles.build(provider: "myspace", uid: "1", username: "tom")).not_to be_valid
  end

  it "builds the profile URL from the username" do
    profile = described_class.new(provider: "github", username: "octo cat")

    expect(profile.profile_url).to eq("https://github.com/octo%20cat")
    expect(profile.provider_name).to eq("GitHub")
  end

  it "offers only the providers that have an OAuth client" do
    expect(described_class.configured_providers).to eq(%w[github])
    expect(described_class.authorize_origins).to eq(%w[https://github.com])

    allow(Rails.application.config.x).to receive(:social_providers).and_return([])

    expect(described_class.configured_providers).to be_empty
  end
end
