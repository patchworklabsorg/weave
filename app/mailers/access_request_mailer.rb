# frozen_string_literal: true

# Emails for access requests (see AccessRequests). The member's reason goes to
# the approvers only. The member hears the decision, not who made it.
class AccessRequestMailer < ApplicationMailer
  # To one approver: a manager of the group, or a superadmin.
  def requested(request, approver)
    @request = request
    @approver = approver
    @requester = request.user
    @application = request.application
    @group_url = group_url(request.group)
    @why = if request.group.managed_by?(approver)
             "You get this email because you manage the #{request.group.name} group in Weave."
           else
             "You get this email because you are a Weave superadmin and the #{request.group.name} group has no managers."
           end

    mail(
      to: approver.email,
      subject: env_subject("#{@requester.full_name} asks for access to #{@application.name}")
    )
  end

  def decided(request)
    @request = request
    @user = request.user
    @application = request.application
    @profile_url = profile_url

    mail(
      to: @user.email,
      subject: env_subject(request.approved? ? "You now have access to #{@application.name}" : "Your request for #{@application.name} was not approved")
    )
  end

end
