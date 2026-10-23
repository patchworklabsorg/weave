# frozen_string_literal: true

# What the board sees about ID image access and the identity team in one
# month (see BreakGlass and IdentityGovernance): every break-glass request
# and decryption, the state of each notice, the member notices that are
# delayed now, how many times a pre-reviewer opened an image, every identity
# team governance step, every change to a privileged user attribute, and the
# identity team as it is now.
class BreakGlassReport
  attr_reader :month

  def initialize(month)
    @month = month.to_date.beginning_of_month
  end

  def range = month.beginning_of_day..month.end_of_month.end_of_day

  def requests
    BreakGlassRecord.where(created_at: range).includes(:requested_by, :approvers).order(:created_at)
  end

  def decryptions
    BreakGlassDecryption.between(range).includes(:viewer, :break_glass_record, notices: :recipient)
                        .order(:created_at)
  end

  # Delayed member notices, from any month, that still wait.
  def delayed_notices
    BreakGlassNotice.delayed.includes(:delayed_by, break_glass_decryption: :break_glass_record).order(:delayed_at)
  end

  def pre_review_views
    VerificationEvent.where(kind: "document_viewed", created_at: range).count
  end

  # Every identity team governance step in the month (see
  # IdentityGovernance): proposals, approvals, removals, NDA records and the
  # bootstrap.
  def governance_events
    IdentityGovernanceEvent.where(created_at: range).includes(:actor, :subject).order(:created_at, :id)
  end

  # Every grant and revoke of a role in the month, and every change to the
  # admin tier (role), from the permanent log (see PrivilegedAttributeChange).
  def privileged_changes
    PrivilegedAttributeChange.between(range).includes(:actor).order(:changed_at, :id)
  end

  # The identity team as it is now, for the board to check.
  def identity_team = User.identity_team.with_roles.order(:first_name, :last_name)

end
