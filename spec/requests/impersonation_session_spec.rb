# frozen_string_literal: true

require "rails_helper"

# While an admin impersonates someone, the cookie is backed by the admin's
# user_sessions row. Looking for it on the impersonated user used to miss, and
# the miss created an empty row on that user's account, which their sessions
# page then listed as "Legacy Session".
RSpec.describe "Sessions while impersonating", type: :request do
  let(:admin) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified) }

  before { sign_in_via_magic_link(admin) }

  it "does not create a session row on the impersonated user" do
    expect do
      post impersonate_admin_user_path(member)
      get root_path
      get profile_sessions_path
    end.not_to(change { member.user_sessions.count })
  end

  it "keeps the admin's session as the current one" do
    admin_session = admin.user_sessions.sole
    post impersonate_admin_user_path(member)

    travel 1.hour do
      get root_path
    end

    expect(admin_session.reload.last_seen_at).to be > 30.minutes.from_now
    expect(admin.user_sessions.count).to eq(1)
  end

  it "returns to the admin account when impersonation stops" do
    post impersonate_admin_user_path(member)

    delete stop_impersonating_admin_users_path

    expect(session[:user_id]).to eq(admin.id)
    expect(session[:admin_id]).to be_nil
    expect(member.user_sessions.count).to eq(0)
  end
end
