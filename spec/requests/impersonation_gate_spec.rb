# frozen_string_literal: true

require "rails_helper"

# Impersonating a member who has not confirmed the email address lands on
# /email_confirmation, which renders in the focus layout. That layout had no
# impersonation banner, so the admin had no visible way back.
RSpec.describe "Impersonating a member stopped at the email gate", type: :request do
  let(:admin) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :unverified, confirmation_sent_at: 1.hour.ago) }

  before do
    sign_in_via_magic_link(admin)
    post impersonate_admin_user_path(member)
  end

  it "shows the stop impersonating control on the confirmation page" do
    get email_confirmation_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(stop_impersonating_admin_users_path)
    expect(response.body).not_to include("Resend confirmation email")
  end

  it "does not send the member a confirmation email" do
    expect do
      post resend_email_confirmation_path
    end.not_to have_enqueued_mail

    expect(response).to redirect_to(email_confirmation_path)
  end

  it "returns to the admin account from the confirmation page" do
    delete stop_impersonating_admin_users_path

    expect(session[:user_id]).to eq(admin.id)
    expect(session[:admin_id]).to be_nil
  end
end
