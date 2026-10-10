# frozen_string_literal: true

require "rails_helper"

# The `introspect` scope lets an app read the app tokens of other apps, so only
# a superadmin may add or remove it. Any admin may change the other scopes.
RSpec.describe "Admin OAuth application scopes", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:application) do
    Doorkeeper::Application.create!(name: "Quilt", redirect_uri: "https://quilt.example.com/cb", scopes: "profile")
  end

  def update_scopes(scopes)
    patch admin_oauth_application_path(application), params: { doorkeeper_application: { scopes: scopes } }
  end

  def create_app(scopes)
    post admin_oauth_applications_path, params: {
      doorkeeper_application: { name: "New", redirect_uri: "https://new.example.com/cb", scopes: scopes }
    }
  end

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "can allow the quilt and directory scopes" do
      update_scopes("profile quilt directory")

      expect(response).to redirect_to(admin_oauth_application_path(application))
      expect(application.reload.scopes.to_a).to contain_exactly("profile", "quilt", "directory")
    end

    it "can't allow the introspect scope" do
      update_scopes("profile introspect")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Only a superadmin can add or remove the introspect scope.")
      expect(application.reload.scopes.to_a).to eq(["profile"])
    end

    it "can't remove the introspect scope" do
      application.update!(scopes: "profile introspect")

      update_scopes("profile")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(application.reload.scopes.to_a).to contain_exactly("profile", "introspect")
    end

    it "can change other scopes of an app that has the introspect scope" do
      application.update!(scopes: "profile introspect")

      update_scopes("profile email introspect")

      expect(application.reload.scopes.to_a).to contain_exactly("profile", "email", "introspect")
    end

    it "can't create an app with the introspect scope" do
      expect { create_app("introspect") }.not_to change(Doorkeeper::Application, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "can allow and remove the introspect scope" do
      update_scopes("profile introspect")
      expect(application.reload.scopes.to_a).to contain_exactly("profile", "introspect")

      update_scopes("profile")
      expect(application.reload.scopes.to_a).to eq(["profile"])
    end

    it "can create an app with the introspect scope" do
      expect { create_app("introspect") }.to change(Doorkeeper::Application, :count).by(1)
    end
  end
end
