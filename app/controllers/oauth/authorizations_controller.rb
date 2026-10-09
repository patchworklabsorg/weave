# frozen_string_literal: true

module Oauth
  # Doorkeeper's authorization endpoint, with one addition: the consent forms
  # are allowed to submit their way to the client's registered redirect URI.
  #
  # Weave's global CSP sets `form-action 'self'` (see
  # config/initializers/content_security_policy.rb), and Chrome and Safari apply
  # form-action to *every hop* of a form submission's redirect chain, not just to
  # the form's own action. Granting consent POSTs same-origin to /oauth/authorize,
  # which answers `302` to the client's redirect_uri — a cross-origin hop the
  # browser then refuses to make, and refuses silently. Server-side nothing looks
  # wrong: Rails logs the POST, logs "Redirected to https://client/...", and
  # returns 302. The client simply never receives the code, so no token exchange
  # ever follows, and the user sees an Authorize button that does nothing at all.
  #
  # Firefox does not enforce form-action across redirects, so this breaks for
  # only some people, which is worse than breaking for everyone.
  #
  # The allowance is derived from what the application registered, never from the
  # redirect_uri parameter, so a crafted request cannot widen the policy by
  # asking to be sent somewhere new. Doorkeeper has already checked the parameter
  # against this same list before any consent screen renders.
  #
  # It also refuses users who may not use a restricted app (see AppAccess).
  # The check runs after sign-in and before consent, for both the consent
  # screen and the consent POST, so a previously approved app can't skip it.
  # The user sees a Weave page instead of a redirect to the client with
  # `error=access_denied`: the client can't grant access, and Weave can say who
  # to ask. A user who only lacks the code of conduct is sent to accept it, and
  # comes back here afterwards (see SlackOnboardingController).
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    include OauthClientRedirectOrigins

    before_action :require_app_access, only: [:new, :create] # rubocop:disable Rails/LexicallyScopedActionFilter -- both are defined by Doorkeeper::AuthorizationsController

    content_security_policy do |policy|
      policy.form_action(:self, *redirect_origins_for(pre_auth.client&.application))
    end

    private

    def require_app_access
      # PreAuthorization finds the client only while it validates, so validate
      # first. A request that is not valid is Doorkeeper's error to report.
      return unless pre_auth.authorizable?

      application = pre_auth.client.application
      decision = AppAccess.explain(current_resource_owner, application)
      return if decision.permitted?

      if decision.reason == :code_of_conduct && request.get?
        session[:code_of_conduct_return_to] = request.fullpath
        redirect_to slack_onboarding_path, alert: "Please accept the Code of Conduct to continue to #{application.name}."
        return
      end

      # Ahoy drops requests it takes for bots, so the log line is the record
      # that is always kept.
      Rails.logger.info("OAuth access denied: user=#{current_resource_owner.p_id} application=#{application.uid}")
      ahoy.track "OAuth access denied", application_uid: application.uid, user_id: current_resource_owner.id
      @application = application
      @decision = decision
      render "doorkeeper/authorizations/access_denied", status: :forbidden
    end

  end
end
