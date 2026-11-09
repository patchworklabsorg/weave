# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]
  layout "sessions"

  def index
    # Anonymous visitors get the "you found the front door" splash.
    return unless current_user

    # An unconfirmed email sees no apps: authenticate_user! sends it to the
    # confirmation page and comes back here after.
    return authenticate_user! unless current_user.email_verified?

    # Joining the Slack (which includes accepting the code of conduct) is part
    # of becoming a member, so anyone who hasn't finished lands on the next
    # step of that instead. A sponsored project can waive the Slack steps (see
    # User#onboarding_pending?).
    return redirect_to(slack_onboarding_path) if current_user.onboarding_pending?

    # Members land on their home: what needs doing, then their apps.
    @user = current_user
    @tasks = MemberTasks.for(@user)
    @launcher = AppLauncher.for(@user)
    render :dashboard, layout: "application"
  end

end
