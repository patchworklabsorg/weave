# frozen_string_literal: true

class HomeController < ApplicationController
  # before_action :authenticate_user
  skip_before_action :authenticate_user!, only: [:index]
  layout false

  def index
    # Signed-in members land on their account dashboard, not the
    # "you found the front door" splash (which is for anonymous visitors).
    # Joining the Slack (which includes accepting the code of conduct) is part
    # of becoming a member, so anyone who hasn't finished lands on the next
    # step of that instead.
    return unless current_user

    onboarding = current_user.email_verified? && !current_user.slack_onboarding_complete?
    redirect_to(onboarding ? slack_onboarding_path : profile_path)
  end

end
