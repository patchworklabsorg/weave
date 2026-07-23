# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe ".generate_secure_password" do
    it "always satisfies the password complexity policy" do
      20.times do
        password = described_class.generate_secure_password

        expect(password.length).to be >= 8
        expect(password).to match(/[A-Z]/)
        expect(password).to match(/[a-z]/)
        expect(password).to match(/\d/)
        expect(password).to match(/[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/)

        user = build(:user, password: password, password_confirmation: password)
        expect(user).to be_valid
      end
    end
  end

  describe "#destroy with dependent OAuth records" do
    it "destroys OAuth tokens/grants instead of raising a foreign key error" do
      user = create(:user)
      application = Doorkeeper::Application.create!(
        name: "Test App",
        redirect_uri: "https://example.com/callback"
      )
      token = Doorkeeper::AccessToken.create!(
        resource_owner_id: user.id, application: application, scopes: ""
      )
      grant = Doorkeeper::AccessGrant.create!(
        resource_owner_id: user.id, application: application,
        redirect_uri: "https://example.com/callback", expires_in: 3600, scopes: ""
      )

      expect { user.destroy! }.not_to raise_error

      expect(Doorkeeper::AccessToken.where(id: token.id)).to be_empty
      expect(Doorkeeper::AccessGrant.where(id: grant.id)).to be_empty
    end
  end
end
