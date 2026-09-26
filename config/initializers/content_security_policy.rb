# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https, :unsafe_inline
    policy.connect_src :self, :https
    policy.frame_ancestors :none
    policy.base_uri :self
    # `form-action` is also enforced against every redirect a form submission leads
    # to, not just its immediate target (see the WHATWG/Chromium behavior tracked at
    # https://github.com/w3c/webappsec-csp/issues/8). Both `/oauth/authorize`'s own
    # consent form and (after sign-in) the magic-link confirmation form end an
    # in-progress OAuth flow with a redirect straight to the client's registered,
    # Doorkeeper-validated `redirect_uri` -- on a different origin by definition. With
    # a plain "self" policy a real browser silently drops that redirect and OAuth
    # sign-in never completes. Doorkeeper already validates `redirect_uri` against
    # the registered value, so this isn't opening up an arbitrary-redirect hole; it's
    # widening the CSP to match what Doorkeeper already allows. Production clients are
    # required to register an https redirect_uri (see docs/OAUTH.md); local clients are
    # allowed a plain-http localhost one for development, so http: is permitted only
    # in local environments, mirroring the http/https split already used for the OIDC
    # issuer's protocol (see doorkeeper_openid_connect.rb).
    policy.form_action(*[:self, :https, (Rails.env.local? ? "http:" : nil)].compact)

    # Specify URI for violation reports (optional - uncomment if you want to collect violations)
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate a fresh random nonce per request for permitted inline scripts.
  # (Do NOT use the session id here: a nonce must be unpredictable and unique
  # per response, and the session id is neither.) Inline styles are permitted
  # via :unsafe_inline above so third-party mounted engines (letter_opener,
  # Flipper, Blazer, Mission Control) render correctly.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w(script-src)

  # Report violations without enforcing the policy (useful for testing)
  # Uncomment to test CSP without breaking functionality:
  # config.content_security_policy_report_only = true
end
