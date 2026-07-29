# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailAddressesController, type: :controller do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST #create" do
    it "adds an email address and sends a confirmation" do
      expect {
        post :create, params: { email_address: { email: "second@example.com" } }
      }.to change { user.email_addresses.count }.by(1)
                                                .and have_enqueued_job(EmailAddressConfirmationJob)

      address = user.email_addresses.find_by(email: "second@example.com")
      expect(address.confirmation_token).to be_present
      expect(address).not_to be_primary
      expect(response).to redirect_to(edit_profile_path)
      expect(flash[:notice]).to be_present
    end

    it "rejects an email belonging to another user" do
      other = create(:user)
      expect {
        post :create, params: { email_address: { email: other.email } }
      }.not_to(change { user.email_addresses.count })

      expect(flash[:alert]).to include("has already been taken")
    end
  end

  describe "GET #confirm" do
    let(:address) { create(:email_address, :with_confirmation_token, user: user) }

    it "confirms the address by token" do
      get :confirm, params: { token: address.confirmation_token }

      expect(address.reload.confirmed?).to be(true)
      expect(address.confirmation_token).to be_nil
      expect(flash[:notice]).to include(address.email)
    end

    it "rejects an invalid token" do
      get :confirm, params: { token: "nope" }
      expect(flash[:alert]).to eq("Invalid confirmation token.")
    end

    it "works without being signed in" do
      token = address.confirmation_token
      allow(controller).to receive(:current_user).and_return(nil)

      get :confirm, params: { token: token }

      expect(address.reload.confirmed?).to be(true)
      expect(response).to redirect_to(login_path)
    end
  end

  describe "PATCH #make_primary" do
    it "promotes a confirmed address" do
      address = create(:email_address, :confirmed, user: user)

      patch :make_primary, params: { id: address.public_id }

      expect(user.reload.email).to eq(address.email)
      expect(flash[:notice]).to include(address.email)
    end

    it "refuses an unconfirmed address" do
      address = create(:email_address, user: user)
      original_email = user.email

      patch :make_primary, params: { id: address.public_id }

      expect(user.reload.email).to eq(original_email)
      expect(flash[:alert]).to be_present
    end

    it "cannot touch another user's address" do
      address = create(:email_address, :confirmed, user: create(:user))

      patch :make_primary, params: { id: address.public_id }

      expect(flash[:alert]).to eq("Email address not found.")
    end
  end

  describe "POST #resend_confirmation" do
    it "throttles resends inside the 5-minute window" do
      address = create(:email_address, :with_confirmation_token, user: user)

      post :resend_confirmation, params: { id: address.public_id }

      expect(flash[:alert]).to include("Please wait")
    end

    it "resends after the window" do
      address = create(:email_address, :with_confirmation_token, user: user)
      address.update!(confirmation_sent_at: 10.minutes.ago)

      expect {
        post :resend_confirmation, params: { id: address.public_id }
      }.to have_enqueued_job(EmailAddressConfirmationJob)
      expect(flash[:notice]).to include(address.email)
    end
  end

  describe "DELETE #destroy" do
    it "removes a secondary address" do
      address = create(:email_address, user: user)

      expect {
        delete :destroy, params: { id: address.public_id }
      }.to change { user.email_addresses.count }.by(-1)
    end

    it "refuses to remove the primary address" do
      primary = user.email_addresses.find_by(is_primary: true)

      expect {
        delete :destroy, params: { id: primary.public_id }
      }.not_to(change { user.email_addresses.count })

      expect(flash[:alert]).to include("Primary email address cannot be removed")
    end
  end
end
