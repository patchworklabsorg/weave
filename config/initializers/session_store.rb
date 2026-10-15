# frozen_string_literal: true

# Without expire_after the session cookie has no Expires attribute, so the
# browser drops it when it closes (and mobile browsers close often). People
# then had to request a new magic link on almost every visit (#199), although
# their user_sessions row was still valid for 30 days.
#
# expire_after makes the cookie persistent and renews it on each request. The
# cookie does not decide how long a sign-in lasts: the user_sessions row does
# (expiration_at, from users.session_duration_seconds, default 30 days), and
# SessionAuthenticator rejects the cookie once that row expires or is signed
# out. Keep this value at or above that default. It is in seconds because
# Rack adds it to the local Time.now, where a Duration would shift by an hour
# across a DST change.
#
# The key is the Rails default for this app, so existing cookies stay valid.
Rails.application.config.session_store :cookie_store,
                                       key: "_weave_session",
                                       expire_after: 30.days.to_i
