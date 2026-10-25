# frozen_string_literal: true

# The `data` of each webhook event (see docs/WEBHOOKS.md). Users are named by
# their Patchwork Labs ID (`p_id`), the same value as the OAuth `sub` claim.
# A payload holds only what a service needs to keep its own access in sync:
# no address, no session IP or location.
module WebhookPayloads
  # User columns that change the `user` payload. A save that changes none of
  # them sends no user.updated.
  USER_FIELDS = {
    "first_name"         => "name",
    "last_name"          => "name",
    "email"              => "email",
    "email_confirmed_at" => "email_verified",
    "slack_id"           => "slack_id",
    "status"             => "active",
    "locked_at"          => "active"
  }.freeze

  class << self
    def user(user)
      {
        user: {
          id: user.p_id,
          name: user.full_name,
          email: user.email,
          email_verified: user.email_verified?,
          slack_id: user.slack_id,
          active: user.can_authenticate?
        }
      }
    end

    # The fields of the `user` payload that a save changed.
    def changed_user_fields(changes) = changes.keys.filter_map { |column| USER_FIELDS[column] }.uniq

    # Only the ID: the account and its data are gone.
    def deleted_user(user) = { user: { id: user.p_id } }

    def session(session)
      {
        session: {
          id: session.public_id,
          created_at: session.created_at&.iso8601,
          expires_at: session.expiration_at&.iso8601,
          signed_out_at: session.signed_out_at&.iso8601,
          impersonated: session.impersonated?
        }.merge(session_end(session)),
        user: { id: session.user.p_id }
      }
    end

    # How a session ended, in session.expired only: a sign-out (or a
    # revocation) or the end of its time.
    def session_end(session)
      return {} unless session.expiry_notified_at

      { ended_by: session.signed_out_at ? "sign_out" : "time" }
    end

    # `reason` is why the membership started or ended: added, removed,
    # expired, group_deleted or account_deleted.
    def group_membership(membership, reason:, actor:)
      {
        group: { id: membership.group.public_id, slug: membership.group.slug },
        user: { id: membership.user.p_id },
        source: membership.source,
        reason: reason,
        expires_at: membership.expires_at&.iso8601,
        actor: actor && { id: actor.p_id }
      }
    end

    # The user that PaperTrail records for the current change, if it is a
    # user and not a job name.
    def current_actor
      whodunnit = PaperTrail.request.whodunnit
      whodunnit = whodunnit.call if whodunnit.respond_to?(:call)
      User.find_by(id: whodunnit) if whodunnit.to_s.match?(/\A\d+\z/)
    end

  end
end
