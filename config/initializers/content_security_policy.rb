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
    policy.style_src   :self, :https
    policy.connect_src :self, :https
    policy.frame_ancestors :none
    policy.base_uri :self
    policy.form_action :self

    # Specify URI for violation reports (optional - uncomment if you want to collect violations)
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted inline scripts and inline styles
  # This allows Turbo/Stimulus and inline styles while maintaining CSP protection
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Report violations without enforcing the policy (useful for testing)
  # Uncomment to test CSP without breaking functionality:
  # config.content_security_policy_report_only = true
end
