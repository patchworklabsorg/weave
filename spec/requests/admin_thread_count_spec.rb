# frozen_string_literal: true

require "rails_helper"

# The staff tools for Thread Count, the internal trust score.
RSpec.describe "Admin Thread Count", type: :request do
  let(:admin) { create(:user, :admin, :verified, is_staff: true, first_name: "Sam") }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:member) { create(:user, :verified, first_name: "Ada") }

  describe "the score" do
    it "shows the score on the admin user page, with a link" do
      create(:thread_count_entry, user: member, kind: "board_vouch", level: nil)
      sign_in_via_magic_link(admin)

      get admin_user_path(member)

      expect(response.body).to include("Thread Count", "Open Thread Count")
    end

    it "shows an admin the score but not what it is made of" do
      create(:thread_count_entry, user: member, kind: "board_vouch", level: nil, reason: "Board knows them well")
      sign_in_via_magic_link(admin)

      get admin_user_thread_count_path(member)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-testid="thread-count-score">#{ThreadCount.config.weight('board_vouch').to_i}<))
      expect(response.body).not_to include("Board knows them well", "What the score is made of")
      expect(response.body).to include("Only superadmins and owners")
    end

    it "shows a superadmin what the score is made of" do
      create(:thread_count_entry, user: member, kind: "board_vouch", level: nil, reason: "Board knows them well")
      sign_in_via_magic_link(superadmin)

      get admin_user_thread_count_path(member)

      expect(response.body).to include("What the score is made of", "Board vouch", "Board knows them well")
    end

    it "does not show anyone their own score" do
      sign_in_via_magic_link(admin)

      get admin_user_thread_count_path(admin)
      expect(response).to redirect_to(admin_user_path(admin))

      get admin_user_path(admin)
      expect(response.body).not_to include("Open Thread Count")
    end

    it "keeps out an admin who may not view the user" do
      sign_in_via_magic_link(admin)

      get admin_user_thread_count_path(create(:user, :admin, :verified))

      expect(response).to redirect_to(admin_users_path)
    end

    it "keeps out members" do
      sign_in_via_magic_link(create(:user, :verified))

      get admin_user_thread_count_path(member)

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "vouching" do
    it "records a vouch from the signed-in admin" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", reason: "Mentored them at a hack night" }

      expect(flash[:notice]).to include("Recorded")
      expect(ThreadCount::Entry.sole).to have_attributes(kind: "staff_vouch", author: admin, user: member)
    end

    it "records a vouch on behalf of a board member" do
      board = create(:user, :verified, is_board: true)
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", voucher: board.email, reason: "Board call" }

      expect(ThreadCount::Entry.sole).to have_attributes(kind: "board_vouch", author: board, recorded_by: admin)
    end

    it "refuses a second vouch from the same voucher unless it is a renewal" do
      sign_in_via_magic_link(admin)
      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", reason: "First" }

      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", reason: "Second" }
      expect(flash[:alert]).to include("already vouches")

      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", reason: "Renewed", renew: "1" }
      expect(flash[:notice]).to include("Recorded")
      expect(ThreadCount::Entry.vouches.not_reversed.count).to eq(1)
    end

    it "refuses a vouch on behalf of another admin, so nobody borrows their name and weight" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", voucher: superadmin.email, reason: "x" }

      expect(flash[:alert]).to include("must record their own vouch")
      expect(ThreadCount::Entry.count).to eq(0)
    end

    it "refuses an unknown voucher" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member), params: { kind: "vouch", voucher: "nobody@example.org", reason: "x" }

      expect(flash[:alert]).to include("No Weave account")
    end

    it "refuses an entry on the admin's own account" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(admin), params: { kind: "vouch", voucher: superadmin.email, reason: "x" }

      expect(ThreadCount::Entry.count).to eq(0)
      expect(flash[:alert]).to include("your own account")
    end

    it "lets the voucher withdraw their own vouch" do
      vouch = create(:thread_count_entry, user: member, author: admin)
      sign_in_via_magic_link(admin)

      get admin_user_thread_count_path(member)
      expect(response.body).to include("Withdraw your vouch")

      patch reverse_admin_user_thread_count_entry_path(member, vouch), params: { reason: "No longer in touch" }

      expect(flash[:notice]).to include("Reversed")
      expect(vouch).to be_reversed
    end

    it "finds an entry by its public id and not by its database id" do
      vouch = create(:thread_count_entry, user: member, author: admin)
      sign_in_via_magic_link(admin)

      patch "/admin/users/#{member.p_id}/thread_count_entries/#{vouch.id}/reverse", params: { reason: "No longer in touch" }

      expect(response).to have_http_status(:not_found)
      expect(vouch.reload).not_to be_reversed
    end
  end

  describe "recording entries" do
    it "records a moderation case with a written reason" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member),
           params: { kind: "moderation_case:major", reason: "Report 12", evidence_url: "https://example.org/12" }

      expect(ThreadCount::Entry.sole).to have_attributes(kind: "moderation_case", level: "major", author: admin, evidence_url: "https://example.org/12")
    end

    it "records an external signal" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member), params: { kind: "external_signal:github_student", reason: "Pack page shown" }

      expect(ThreadCount::Entry.sole).to have_attributes(kind: "external_signal", level: "github_student")
    end

    it "needs a reason" do
      sign_in_via_magic_link(admin)

      post admin_user_thread_count_entries_path(member), params: { kind: "moderation_case:minor", reason: "" }

      expect(flash[:alert]).to include("Reason can't be blank")
      expect(ThreadCount::Entry.count).to eq(0)
    end

    it "lets only a superadmin reverse someone else's entry" do
      entry = create(:thread_count_entry, :moderation_case, user: member)

      sign_in_via_magic_link(admin)
      patch reverse_admin_user_thread_count_entry_path(member, entry), params: { reason: "Wrong" }
      expect(flash[:alert]).to include("Only a superadmin")

      sign_in_via_magic_link(superadmin)
      patch reverse_admin_user_thread_count_entry_path(member, entry), params: { reason: "Wrong member" }
      expect(flash[:notice]).to include("Reversed")
    end

    it "does not let a superadmin reverse an entry about their own account" do
      entry = create(:thread_count_entry, :moderation_case, user: superadmin)
      sign_in_via_magic_link(superadmin)

      patch reverse_admin_user_thread_count_entry_path(superadmin, entry), params: { reason: "Not fair" }

      expect(response).to redirect_to(admin_user_path(superadmin))
      expect(entry).not_to be_reversed
    end

    it "records a deduction only for users below the admin's own access level" do
      owner = create(:user, :owner, :verified)
      other_owner = create(:user, :owner, :verified)
      sign_in_via_magic_link(owner)

      %w[moderation_case:minor project_denied project_blacklisted].each do |kind|
        post admin_user_thread_count_entries_path(other_owner), params: { kind:, reason: "Report" }
        expect(flash[:alert]).to include("below your own access level")
      end
      expect(ThreadCount::Entry.count).to eq(0)

      post admin_user_thread_count_entries_path(member), params: { kind: "project_blacklisted", reason: "Plagiarism" }
      expect(ThreadCount::Entry.sole).to have_attributes(kind: "project_blacklisted", user: member)
    end

    it "needs a reason to reverse" do
      entry = create(:thread_count_entry, user: member)
      sign_in_via_magic_link(superadmin)

      patch reverse_admin_user_thread_count_entry_path(member, entry), params: { reason: " " }

      expect(flash[:alert]).to include("Say why")
      expect(entry).not_to be_reversed
    end

    it "does not reverse an entry through another member's URL" do
      entry = create(:thread_count_entry, user: create(:user, :verified))
      sign_in_via_magic_link(superadmin)

      patch reverse_admin_user_thread_count_entry_path(member, entry), params: { reason: "x" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
