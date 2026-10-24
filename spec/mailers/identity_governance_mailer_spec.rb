# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdentityGovernanceMailer do
  let(:owner) { create(:user, :owner, :verified, first_name: "Olive", last_name: "Owner") }
  let!(:board_member) { create(:user, :verified, is_board: true) }

  before { create(:user, :verified, is_board: true) } # A key holder change needs two board members.

  it "asks a board member to approve, with the reason and the link" do
    subject_user = create(:user, :identity_team, first_name: "Kai", last_name: "Holder")
    create(:verification, :verified, user: subject_user)
    proposal = IdentityGovernance.propose(kind: "add_key_holder", subject: subject_user, by: owner, reason: "Third key holder.").record

    mail = described_class.approval_needed(proposal, board_member)

    expect(mail.to).to eq([board_member.email])
    expect(mail.body.encoded).to include("Olive Owner proposes to make Kai Holder a key holder", "Third key holder.",
                                         "Every board member", "/identity/governance_proposals/#{proposal.to_param}")
  end

  it "tells a board member about a removal, with the reason" do
    member = create(:user, :key_holder, first_name: "Rae", last_name: "Gone")
    event = IdentityGovernance.remove_member(member, by: owner, reason: "Left the org.").record

    mail = described_class.member_removed(event, board_member)

    expect(mail.body.encoded).to include("Olive Owner removed Rae Gone from the identity team", "Left the org.",
                                         "was a key holder")
  end

  it "tells a board member about a board change" do
    joining = create(:user, :verified, is_board: true, first_name: "Nia", last_name: "New")
    event = IdentityGovernance.board_changed!(joining, by: owner)

    mail = described_class.board_changed(event, board_member)

    expect(mail.to).to eq([board_member.email])
    expect(mail.body.encoded).to include("Olive Owner added Nia New to the board", "Only an owner can change the board")
  end
end
