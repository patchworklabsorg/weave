# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Password sign-in with Active Directory", type: :request do
  let(:directory) { use_fake_directory }
  let(:user) { create(:user, :verified) }

  def sign_in_with_password(email, password)
    post "/login", params: { user: { email: email, password: password } }
  end

  before do
    directory.add_user(user.p_id, password: "Ad-password-1")
    DirectoryPasswords.link(user)
    directory.binds.clear
  end

  it "signs in a linked member with their AD password" do
    expect { sign_in_with_password(user.email, "Ad-password-1") }.to change { user.user_sessions.count }.by(1)

    expect(response).to have_http_status(:redirect)
    expect(session[:user_id]).to eq(user.id)
  end

  it "refuses a password from a member who is not linked yet, and does not ask AD" do
    member = create(:user, :verified)
    directory.add_user(member.p_id, password: "Ad-password-1")

    sign_in_with_password(member.email, "Ad-password-1")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Invalid email or password")
    expect(session[:user_id]).to be_nil
    expect(directory.binds).to be_empty
    expect(member.reload.directory_linked_at).to be_nil
  end

  it "has no separate password sign-in page" do
    get "/login/pw"

    expect(response).to have_http_status(:not_found)
  end

  it "refuses the old Weave password once the user is linked" do
    sign_in_with_password(user.email, "SecurePassword123!")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Invalid email or password")
    expect(session[:user_id]).to be_nil
  end

  it "uses the same message for an unknown email and a wrong password" do
    sign_in_with_password("nobody@example.com", "whatever")
    unknown = response.body[/Invalid email or password/]

    sign_in_with_password(user.email, "wrong")

    expect(unknown).to be_present
    expect(response.body).to include(unknown)
  end

  it "does not ask AD about an account Weave has locked" do
    user.update_column(:locked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

    sign_in_with_password(user.email, "Ad-password-1")

    expect(session[:user_id]).to be_nil
    expect(directory.binds).to be_empty
  end

  it "tells a locked AD account to wait" do
    directory.account(user.p_id).bind_error = "775"

    sign_in_with_password(user.email, "Ad-password-1")

    expect(response.body).to include("Too many failed sign-in attempts")
    expect(session[:user_id]).to be_nil
  end

  it "does not tell a guesser that the password of a disabled AD account is right" do
    directory.account(user.p_id).bind_error = "533"

    sign_in_with_password(user.email, "Ad-password-1")

    expect(response.body).to include("Invalid email or password")
    expect(session[:user_id]).to be_nil
  end

  it "says password sign-in is unavailable when no DC answers, and does not fall back to the Weave password" do
    directory.down_hosts.push("loom.patchwork.internal", "spindle.patchwork.internal")

    sign_in_with_password(user.email, "SecurePassword123!")

    expect(response.body).to include("Password sign-in is not available now")
    expect(session[:user_id]).to be_nil
  end

  describe "an expired password (AD 773 or 532)" do
    before { directory.account(user.p_id).bind_error = "773" }

    it "sends the user to choose a new password, and the change goes to AD" do
      sign_in_with_password(user.email, "Ad-password-1")
      expect(response).to redirect_to(expired_password_path)
      expect(session[:user_id]).to be_nil

      patch expired_password_path, params: { current_password: "Ad-password-1", password: "New-password-2", password_confirmation: "New-password-2" }

      expect(response).to redirect_to(login_path)
      expect(directory.account(user.p_id).password).to eq("New-password-2")
      expect(directory.modifications.last[:operations].map(&:first)).to eq(%i[delete add])

      sign_in_with_password(user.email, "New-password-2")
      expect(session[:user_id]).to eq(user.id)
    end

    it "shows the AD policy refusal" do
      sign_in_with_password(user.email, "Ad-password-1")
      directory.modify_error = { code: 19, message: "0000052D: Constraint violation" }

      patch expired_password_path, params: { current_password: "Ad-password-1", password: "short", password_confirmation: "short" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("does not meet the Patchwork password policy")
    end

    it "refuses the page without a recent sign-in attempt" do
      get expired_password_path

      expect(response).to redirect_to(login_path)
    end

    it "expires the pending change after ten minutes" do
      sign_in_with_password(user.email, "Ad-password-1")

      travel 11.minutes do
        get expired_password_path
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "rate limits" do
    it "throttles password attempts for one email" do
      5.times { sign_in_with_password(user.email, "wrong") }

      sign_in_with_password(user.email, "Ad-password-1")

      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles password attempts sent to /login.json" do
      5.times { post "/login.json", params: { user: { email: user.email, password: "wrong" } } }

      post "/login.json", params: { user: { email: user.email, password: "Ad-password-1" } }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles password attempts sent as a JSON body" do
      5.times { post "/login", params: { user: { email: user.email, password: "wrong" } }.to_json, headers: { "CONTENT_TYPE" => "application/json" } }

      post "/login", params: { user: { email: user.email, password: "Ad-password-1" } }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "stops binding for a user after five failures, even from a new IP" do
      # Five failures that came in through other IPs and other app processes.
      DirectoryPasswords::MAX_FAILURES.times { DirectoryPasswords.sign_in(user, "wrong") }

      binds_before = directory.binds.size
      post "/login", params: { user: { email: user.email, password: "Ad-password-1" } }, env: { "REMOTE_ADDR" => "10.0.0.99" }

      expect(response.body).to include("Too many failed sign-in attempts")
      expect(directory.binds.size).to eq(binds_before)
    end
  end

  describe "users without an AD account" do
    let(:admin) { create(:user, :admin, :verified) }

    it "keeps Weave's own password sign-in for admins" do
      sign_in_with_password(admin.email, "SecurePassword123!")

      expect(session[:user_id]).to eq(admin.id)
      expect(admin.reload.directory_linked_at).to be_nil
    end

    it "refuses Weave's own password for a member, with the wrong-password message" do
      member = create(:user, :verified)

      sign_in_with_password(member.email, "SecurePassword123!")

      expect(response.body).to include("Invalid email or password")
      expect(session[:user_id]).to be_nil
    end
  end

  describe "an admin linked to AD" do
    let(:admin) { create(:user, :admin, :verified) }

    before do
      directory.add_user(admin.p_id, password: "Admin-ad-password-1")
      DirectoryPasswords.link(admin, explicit: true)
      directory.binds.clear
    end

    it "signs in with the AD password, not the old Weave password" do
      sign_in_with_password(admin.email, "SecurePassword123!")
      expect(response.body).to include("Invalid email or password")
      expect(session[:user_id]).to be_nil

      sign_in_with_password(admin.email, "Admin-ad-password-1")
      expect(session[:user_id]).to eq(admin.id)
      expect(directory.binds.map(&:last)).to include(directory.account(admin.p_id).dn)
    end
  end

  describe "with AD turned off" do
    before { use_fake_directory(FakeDirectory.new, env: { "AD_ENABLED" => "false" }) }

    it "keeps Weave's own password sign-in for admins" do
      admin = create(:user, :admin, :verified)

      sign_in_with_password(admin.email, "SecurePassword123!")

      expect(session[:user_id]).to eq(admin.id)
    end

    it "refuses a member's Weave password" do
      member = create(:user, :verified)

      sign_in_with_password(member.email, "SecurePassword123!")

      expect(response.body).to include("Invalid email or password")
      expect(session[:user_id]).to be_nil
    end
  end

  it "answers a JSON password attempt from an unlinked member with 401 and the wrong-password message" do
    member = create(:user, :verified)
    directory.add_user(member.p_id, password: "Ad-password-1")

    post "/login.json", params: { user: { email: member.email, password: "Ad-password-1" } }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("Invalid email or password")
    expect(directory.binds).to be_empty
  end

  describe "POST /auth/check_password_login" do
    it "offers the password field to a linked user without asking AD" do
      user.update_column(:directory_linked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      directory

      post "/auth/check_password_login", params: { email: user.email }, as: :json

      expect(response.parsed_body["password_login_enabled"]).to be(true)
      expect(directory.binds).to be_empty
    end

    it "does not offer it to a member who is not linked yet" do
      user.update_column(:directory_linked_at, nil) # rubocop:disable Rails/SkipsModelValidations

      post "/auth/check_password_login", params: { email: user.email }, as: :json

      expect(response.parsed_body["password_login_enabled"]).to be(false)
    end
  end

  it "links the user in the background after an email-link sign-in" do
    user.update_columns(directory_linked_at: nil, directory_object_guid: nil) # rubocop:disable Rails/SkipsModelValidations
    expect { sign_in_via_magic_link(user) }.to have_enqueued_job(LinkDirectoryAccountJob).with(user.id)

    perform_enqueued_jobs { LinkDirectoryAccountJob.perform_later(user.id) }

    expect(user.reload.directory_linked_at).to be_present
  end
end
