# frozen_string_literal: true

# Emails the identity team leads each day while deletion requests are past
# their review date (deletion.review_sla_days), so review can't become a
# stall.
class DeletionReviewReminderJob < ApplicationJob
  queue_as :default

  def perform
    overdue = DeletionRequest.review_overdue.order(:review_due_at).to_a
    return if overdue.empty?

    User.identity_leads.find_each { |lead| DataHandlingMailer.reviews_overdue(lead, overdue).deliver_now }
  end

end
