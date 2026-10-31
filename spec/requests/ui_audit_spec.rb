# frozen_string_literal: true

require "rails_helper"

# The fixes from the 2026-10-25 UI audit that a request can check: the skip
# link and main landmark in every layout, the impersonate confirmation on a
# Turbo-off form, one primary button per page, and titles on the focus pages.
RSpec.describe "UI audit fixes", type: :request do
  let(:owner) { create(:user, :owner, :verified, :accepted_code_of_conduct) }
  let(:member) { create(:user, :verified, :accepted_code_of_conduct, first_name: "Ada") }

  def primary_buttons
    response.body.scan(/btn-primary/).size
  end

  describe "skip link and main landmark" do
    it "is in the focus layout" do
      get login_path

      expect(response.body).to include('class="skip-link"')
      expect(response.body).to include('id="main"')
    end

    it "is in the member and admin layouts" do
      sign_in_via_magic_link(owner)

      get profile_path
      expect(response.body).to include('class="skip-link"')
      expect(response.body).to include('<main id="main"')

      get admin_users_path
      expect(response.body).to include('class="skip-link"')
      expect(response.body).to include('<main id="main"')
      expect(response.body).to include('data-drawer-target="content"')
    end
  end

  describe "impersonation confirmation" do
    before do
      member
      sign_in_via_magic_link(owner)
    end

    # data-turbo-confirm does nothing on a form with Turbo off, so the confirm
    # must go through the confirm-submit controller on the form itself.
    it "asks through confirm-submit on the users list" do
      get admin_users_path

      form = response.body[/<form[^>]*#{Regexp.escape(impersonate_admin_user_path(member))}[^>]*>/]
      expect(form).to include('data-turbo="false"')
      expect(form).to include('data-controller="confirm-submit"')
      expect(form).to include("Sign in as Ada")
      expect(response.body).not_to include("data-turbo-confirm=\"Are you sure you want to impersonate")
    end

    it "asks through confirm-submit on the user page, where Edit is the primary action" do
      get admin_user_path(member)

      form = response.body[/<form[^>]*#{Regexp.escape(impersonate_admin_user_path(member))}[^>]*>/]
      expect(form).to include('data-controller="confirm-submit"')
      expect(response.body).to include("Edit user")
      expect(response.body).not_to include("Edit User")
      expect(primary_buttons).to eq(1)
    end
  end

  describe "one primary button per page" do
    it "holds on the member profile while onboarding is pending" do
      user = create(:user, :verified, birthday: nil)
      sign_in_via_magic_link(user)

      get profile_path

      expect(response.body).to include("Add your birthday")
      expect(primary_buttons).to eq(1)
    end
  end

  describe "focus page titles" do
    it "names the sign-in page" do
      get login_path

      expect(response.body).to include("<title>Sign in · Weave</title>")
    end

    it "names the magic link confirmation" do
      link = User::MagicLink.issue!(member)

      get magic_link_login_path(token: link.token)

      expect(response.body).to include("<title>Confirm your sign in · Weave</title>")
    end
  end

  describe "the fallback sign-in form" do
    it "submits without scripts" do
      post login_path, params: { user: { email: "nobody@example.com", password: "x" } },
                       headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("Send magic link")
      expect(response.body).not_to match(/<input[^>]*type="submit"[^>]*disabled/)
    end
  end

  describe "the static error pages" do
    it "carry the dark theme tokens" do
      %w[400 404 422 500 503 406-unsupported-browser].each do |code|
        html = Rails.root.join("public/#{code}.html").read
        expect(html).to include("@media (prefers-color-scheme: dark)"), "#{code}.html has no dark tokens"
        expect(html).to include("--on-grape"), "#{code}.html button text is not tokenized"
      end
    end
  end
end
