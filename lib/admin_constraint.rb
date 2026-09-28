# frozen_string_literal: true

# Guards the /admin namespace, including the engines mounted there (Blazer,
# Flipper, Mission Control, Audits1984) that have no authentication of their
# own. It runs before any controller does, so it validates the session through
# SessionAuthenticator rather than trusting session[:user_id]: otherwise a
# signed-out or expired admin cookie, or a suspended admin, still gets in.
class AdminConstraint
  def matches?(request)
    user = SessionAuthenticator.new(request.session).user
    return false unless user

    user.admin?
  end

end
