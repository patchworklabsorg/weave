# frozen_string_literal: true

# Email for data handling, takeout and deletion (see DeletionPipeline,
# Takeout and DormancyJob). Every email links to "What we do with your data"
# (the mailer layout does too). The text is in
# config/locales/data_handling.en.yml.
class DataHandlingMailer < ApplicationMailer
  # The receipt goes to a person whose account is gone. Ahoy would keep the
  # address in ahoy_messages, so this email keeps no history.
  before_action(only: :deletion_receipt) { self.ahoy_options = ahoy_options.merge(message: false) }
  before_action { @data_page_url = Weave.data_page_url }

  def takeout_ready(takeout)
    @user = takeout.user
    @takeout = takeout
    @url = takeout_url

    mail(to: @user.email, subject: env_subject(t("data_handling.mailer.takeout_ready.subject")))
  end

  def deletion_requested(request)
    @deletion_request = request
    @user = request.user
    @url = deletion_request_url

    mail(to: request.receipt_email, subject: env_subject(t("data_handling.mailer.deletion_requested.subject")))
  end

  def deletion_rejected(request)
    @deletion_request = request
    @user = request.user

    mail(to: request.receipt_email, subject: env_subject(t("data_handling.mailer.deletion_rejected.subject")))
  end

  # Step 4 of the deletion pipeline. Lists what was removed, what was
  # retained and under which obligation. Holds no value from the account.
  def deletion_receipt(request)
    @deletion_request = request
    @receipt = request.receipt
    @categories = DataCategories.all.index_by(&:key)

    mail(to: request.receipt_email, subject: env_subject(t("data_handling.mailer.deletion_receipt.subject")))
  end

  def dormancy_warning(user, days_before:, deadline:)
    @user = user
    @days_before = days_before
    @deadline = deadline
    @login_url = login_url

    mail(to: user.email, subject: env_subject(t("data_handling.mailer.dormancy_warning.subject", days: days_before)))
  end

  # To the identity team leads. No member data beyond the Weave ID.
  def review_needed(request, lead)
    @deletion_request = request
    @admin_url = admin_deletion_request_url(request)

    mail(to: lead.email, subject: env_subject("[IDP] Deletion request to review, due #{request.review_due_at.to_date.to_fs(:long)}"))
  end

  def reviews_overdue(lead, requests)
    @requests = requests
    @admin_url = admin_deletion_requests_url

    mail(to: lead.email, subject: env_subject("[IDP Alert] #{requests.size} deletion request(s) past the review date"))
  end

end
