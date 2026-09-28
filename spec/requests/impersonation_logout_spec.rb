# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Logging out while impersonating", type: :request do
  let(:admin) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified) }

  before do
    sign_in_via_magic_link(admin)
    post impersonate_admin_user_path(member)
  end

  it "returns to the admin account" do
    delete logout_path

    expect(response).to redirect_to(admin_users_path)
    expect(session[:user_id]).to eq(admin.id)
    expect(session[:admin_id]).to be_nil
  end

  it "signs out completely when the admin was deleted in the meantime" do
    admin.destroy!

    delete logout_path

    expect(response).to redirect_to(login_path)
    expect(session[:user_id]).to be_nil
    expect(session[:admin_id]).to be_nil
  end
end
