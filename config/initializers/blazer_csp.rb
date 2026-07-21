# frozen_string_literal: true

# Blazer's query UI is built with Vue, whose template compiler evaluates
# strings as JavaScript via `new Function(...)`. That requires `unsafe-eval`
# in the CSP `script-src`.
#
# Rather than weaken the application-wide policy (this is an OAuth identity
# provider — `unsafe-eval` on scripts everywhere would be a real XSS
# regression), we relax the policy for Blazer's controllers ONLY. Blazer is
# mounted behind admin auth, so the blast radius is limited to authenticated
# admins. `unsafe-eval` is a keyword source and applies regardless of the
# per-response script nonce, so the rest of the strict policy still holds.
Rails.application.config.to_prepare do
  if defined?(Blazer::BaseController)
    Blazer::BaseController.content_security_policy do |policy|
      policy.script_src :self, :https, :unsafe_inline, :unsafe_eval
    end
  end
end
