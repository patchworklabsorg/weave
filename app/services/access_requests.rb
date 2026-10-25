# frozen_string_literal: true

# Self-service access to restricted OAuth apps (see AccessRequest).
#
# 1. A member who may not use an app asks for access with a reason. The app
#    must name an access request group (OauthApplicationLauncher).
# 2. Weave emails the group's managers. A group with no managers falls back
#    to the superadmins.
# 3. A manager or a superadmin approves or denies (AccessRequestPolicy).
#    Approval adds the member to the group. Weave emails the member either way.
#
# Approval gives access only through the group, so AppAccess stays the one
# place that decides who may use an app.
module AccessRequests
  Error = Class.new(StandardError)

  class << self
    # Whether the user may ask for access to the app now. Only a plain "no
    # grant" refusal can be fixed by a group: a missing code of conduct, a
    # missing consent or verification has its own path.
    def requestable?(user, application)
      return false unless user && application
      return false unless request_group_for(application)
      return false if AccessRequest.pending.exists?(user:, application:)
      # The group can't give an address on the app's email domains.
      return false if AppAccess.email_domain_required?(application) && AppAccess.email_for(user, application).nil?

      AppAccess.explain(user, application).reason == :no_grant
    end

    # The group an approval adds the member to, while it still gives access
    # to the app. nil when the app takes no requests.
    def request_group_for(application)
      group = application.access_request_group
      return unless group&.manual?
      # Joining a sponsored project group turns off onboarding steps (see
      # Group), so it never takes requests.
      return if group.waives_code_of_conduct || group.waives_slack
      return unless AppAccess.linked_groups(application).exists?(id: group.id)

      group
    end

    def pending_for(user, application) = AccessRequest.pending.find_by(user:, application:)

    # Creates the request and emails the approvers. Returns the request; check
    # #persisted? for errors.
    def request!(user:, application:, reason:)
      request = AccessRequest.new(user:, application:, reason: reason.to_s.strip, group: request_group_for(application))
      unless requestable?(user, application)
        request.errors.add(:base, "You can't ask for access to this app.")
        return request
      end

      begin
        saved = request.save
      rescue ActiveRecord::RecordNotUnique
        request.errors.add(:base, "You already asked for access to this app.")
        saved = false
      end
      notify_approvers(request) if saved
      request
    end

    # Adds the member to the group and records the decision. The row lock on
    # the request stops two managers from deciding at once. Approval fails,
    # and changes nothing, when the group no longer takes the app's requests
    # or the membership would still not let the member in.
    def approve!(request, by:)
      decide!(request, by:, status: "approved") do
        unless request_group_for(request.application) == request.group
          raise Error, "#{request.application.name} no longer takes requests through #{request.group.name}."
        end

        membership = request.group.memberships.find_or_initialize_by(user: request.user)
        if membership.new_record? || membership.expired?
          # A renewed row starts again as a plain member: only a superadmin
          # makes managers.
          membership.assign_attributes(expires_at: nil, added_by: by, source: "manual", role: "member")
          membership.save!
        end
        unless AppAccess.permitted?(request.user, request.application)
          raise Error, "#{request.user.full_name} still can't use #{request.application.name} after joining #{request.group.name}."
        end
      end
    end

    # Closes the pending requests that no longer go to the app's request
    # group, so the member can ask again. Runs when the request group changes
    # or the group is deleted. Weave sends no email: nobody decided.
    def cancel_stale!(application)
      group = request_group_for(application)
      stale = application.access_requests.pending
      stale = stale.where.not(group_id: group.id) if group
      stale.find_each { |request| request.update!(status: "cancelled", decided_at: Time.current) }
    end

    def deny!(request, by:) = decide!(request, by:, status: "denied")

    # The people Weave emails about a new request.
    def approvers(request)
      managers = request.group.managers.where.not(id: request.user_id).to_a
      managers.presence || User.superadmin.where.not(id: request.user_id).to_a
    end

    private

    def decide!(request, by:, status:)
      AccessRequest.transaction do
        request.lock!
        raise Error, "This request was already decided." unless request.pending?

        yield if block_given?
        request.update!(status:, decided_by: by, decided_at: Time.current)
      end
      AccessRequestMailer.decided(request).deliver_later
      request
    end

    def notify_approvers(request)
      approvers(request).each do |approver|
        AccessRequestMailer.requested(request, approver).deliver_later
      end
    end

  end
end
