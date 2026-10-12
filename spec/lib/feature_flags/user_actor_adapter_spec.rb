# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureFlags::UserActorAdapter do
  let!(:user) { create(:user, email: "ada@example.com") }
  let(:feature) { Flipper[:spec_flag] }

  before { stub_const("FeatureFlags::FLAGS", { spec_flag: "A flag for specs" }) }

  # The Flipper UI wraps each typed value in Flipper::Actor, as these examples do.
  def typed(value) = Flipper::Actor.new(value)

  # Saves a gate in the store adapter, past this one, as a gate saved before
  # this adapter existed.
  def save_raw(value)
    store = Flipper.adapter
    store = store.adapter while store.respond_to?(:adapter)
    store.enable(feature, feature.gate(:actor), Flipper::Types::Actor.new(typed(value)))
  end

  describe "enable" do
    it "saves an email as the user's flipper_id" do
      feature.enable_actor(typed(" Ada@Example.com "))

      expect(feature.actors_value).to eq(Set[user.flipper_id])
      expect(Flipper.enabled?(:spec_flag, user)).to be(true)
    end

    it "saves a public id and a lowercase p_id as the user's flipper_id" do
      feature.enable_actor(typed(user.public_id))
      feature.enable_actor(typed(user.p_id.downcase))

      expect(feature.actors_value).to eq(Set[user.flipper_id])
    end

    it "saves a user passed by code unchanged" do
      feature.enable_actor(user)

      expect(feature.actors_value).to eq(Set[user.flipper_id])
    end

    it "raises for a value that matches no user and saves nothing" do
      expect { feature.enable_actor(typed("nobody@example.com")) }
        .to raise_error(described_class::UnknownActor, /"nobody@example.com" matches no user/)
      expect(feature.actors_value).to be_empty
    end
  end

  describe "disable" do
    it "removes the user's gate when the admin types an email" do
      feature.enable_actor(user)
      feature.disable_actor(typed(user.email))

      expect(feature.actors_value).to be_empty
    end

    it "removes a gate that was saved as an email before the adapter" do
      save_raw(user.email)
      feature.disable_actor(typed(user.email))

      expect(feature.actors_value).to be_empty
    end

    it "removes a gate that matches no user" do
      save_raw("nobody@example.com")
      feature.disable_actor(typed("nobody@example.com"))

      expect(feature.actors_value).to be_empty
    end
  end

  it "passes other gates through unchanged" do
    feature.enable_group(:admins)

    expect(feature.groups_value).to eq(Set["admins"])
  end

  describe described_class::UnknownActorRedirect do
    it "sends the admin back to the add-actor form with the error" do
      app = ->(_env) { raise FeatureFlags::UserActorAdapter::UnknownActor, "\"x\" matches no user." }
      env = Rack::MockRequest.env_for("/features/spec_flag/actors", method: "POST", "SCRIPT_NAME" => "/admin/flipper")

      status, headers, = described_class.new(app).call(env)

      expect(status).to eq(302)
      expect(headers["location"]).to eq("/admin/flipper/features/spec_flag/actors?error=%22x%22+matches+no+user.")
    end

    it "passes a normal response through" do
      app = ->(_env) { [200, {}, ["ok"]] }

      expect(described_class.new(app).call(Rack::MockRequest.env_for("/"))).to eq([200, {}, ["ok"]])
    end
  end
end
