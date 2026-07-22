# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::UsersController, type: :controller do
  def stub_actor(actor)
    allow(controller).to receive_messages(
      current_user: actor,
      authenticate_user!: true,
      require_admin: true,
      track_user_session: true,
      current_user_session: nil
    )
  end

  let(:admin) { create(:user, :admin, :verified) }
  let(:owner) { create(:user, :owner, :verified) }
  let(:target) { create(:user, :verified) }

  describe "PATCH #update privilege enforcement" do
    it "does not let a plain admin promote a user to owner" do
      stub_actor(admin)

      patch :update, params: { id: target.to_param, user: { role: "owner" } }

      expect(target.reload.role).to eq("user")
    end

    it "does not let a plain admin promote themselves" do
      stub_actor(admin)

      patch :update, params: { id: admin.to_param, user: { role: "owner" } }

      expect(admin.reload.role).to eq("admin")
    end

    it "does not let a plain admin change an owner's password" do
      stub_actor(admin)
      old_digest = owner.password_digest

      patch :update, params: {
        id: owner.to_param,
        user: { password: "BrandNewSecret123!", password_confirmation: "BrandNewSecret123!" }
      }

      expect(owner.reload.password_digest).to eq(old_digest)
    end

    it "does not let a plain admin edit a peer admin's role" do
      other_admin = create(:user, :admin, :verified)
      stub_actor(admin)

      patch :update, params: { id: other_admin.to_param, user: { role: "user" } }

      expect(other_admin.reload.role).to eq("admin")
    end

    it "lets an owner promote a user to admin" do
      stub_actor(owner)

      patch :update, params: { id: target.to_param, user: { role: "admin" } }

      expect(target.reload.role).to eq("admin")
    end

    it "still applies non-privileged fields while stripping an illegal role" do
      stub_actor(admin)

      patch :update, params: {
        id: target.to_param,
        user: { first_name: "Renamed", role: "owner" }
      }

      target.reload
      expect(target.first_name).to eq("Renamed")
      expect(target.role).to eq("user")
    end
  end
end
