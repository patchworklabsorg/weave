# frozen_string_literal: true

require "rails_helper"

# Impersonating a member who has not confirmed the email address lands on
# /email_confirmation, which renders in the focus layout. That layout had no
# impersonation banner, so the admin had no visible way back.
RSpec.describe "Impersonating a member stopped at the email gate", type: :request do
  let(:admin) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :unverified) }

  before do
    sign_in_via_magic_link(admin)
    post impersonate_admin_user_path(member)
    # Creating the account sets confirmation_sent_at to now. Move it out of the
    # five-minute wait, so a resend would really reset the token.
    member.update!(confirmation_sent_at: 1.hour.ago)
  end

  it "shows the stop impersonating control on the confirmation page" do
    get email_confirmation_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(stop_impersonating_admin_users_path)
    expect(response.body).not_to include("Resend confirmation email")
  end

  it "does not reset the member's confirmation token" do
    expect do
      post resend_email_confirmation_path
    end.not_to(change { member.reload.attributes.slice("confirmation_token", "confirmation_sent_at") })

    expect(response).to redirect_to(email_confirmation_path)
    expect(flash[:alert]).to eq("You can't send a confirmation email while impersonating a user.")
  end

  it "refuses a turbo_stream resend too" do
    expect do
      post resend_email_confirmation_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.not_to(change { member.reload.confirmation_sent_at })
  end

  it "returns to the admin account through the page's stop impersonating button" do
    get email_confirmation_path
    expect(response.body).to match(/action="#{logout_path}".*Stop impersonating/m)

    delete logout_path

    expect(response).to redirect_to(admin_users_path)
    expect(session[:user_id]).to eq(admin.id)
    expect(session[:admin_id]).to be_nil
  end
end
