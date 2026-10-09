# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/user_mailer/signup
  delegate :signup, to: :UserMailer

  # Preview this email at http://localhost:3000/rails/mailers/user_mailer/slack_email_address_added
  def slack_email_address_added
    UserMailer.slack_email_address_added(EmailAddress.where(is_primary: false).first || EmailAddress.first)
  end

  # Preview this email at http://localhost:3000/rails/mailers/user_mailer/code_of_conduct_request
  def code_of_conduct_request
    user = User.code_of_conduct_pending.first || User.first
    UserMailer.code_of_conduct_request(user, deadline: 3.weeks.from_now.to_date)
  end

end
