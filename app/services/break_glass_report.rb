# frozen_string_literal: true

# What the board sees about ID image access in one month (see BreakGlass):
# every break-glass request and decryption, the state of each notice, the
# member notices that are delayed now, and how many times a pre-reviewer
# opened an image.
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

end
