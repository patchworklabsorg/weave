# frozen_string_literal: true

# Invites a member to the Patchwork Labs Slack workspace.
#
# Fires automatically once a member confirms their email, and can be re-run from
# the admin UI (with resend: true). Idempotent: if the person is already in the
# workspace it syncs their PWL ID instead of inviting again.
class InviteToSlackJob < ApplicationJob
  queue_as :default

  def perform(user_id, resend: false)
    user = User.find_by(id: user_id)
    return unless user

    service = SlackService.new
    unless service.configured?
      Rails.logger.info "Slack not configured for invites; skipping invite for user #{user_id}"
      return
    end

    # Already in the workspace? Don't re-invite (unless explicitly resending) —
    # just make sure their PWL ID is synced.
    unless resend
      existing = begin
        service.find_user_by_email(user.email)
      rescue SlackService::SlackError
        nil
      end
      if existing
        SyncUserToSlackJob.perform_later(user.id)
        return
      end
    end

    # New members join as single-channel guests confined to the code-of-conduct
    # channel; they're promoted to full members once they accept the CoC.
    result = service.invite_to_workspace(
      email: user.email,
      real_name: user.full_name,
      guest: :single_channel
    )

    if result[:ok]
      user.update_columns(slack_invited_at: Time.current) unless result[:already_member] && user.slack_invited_at.present?
      Rails.logger.info "Slack invite #{result[:already_member] ? 'skipped (already member)' : 'sent'} for #{user.email}"
    else
      Rails.logger.error "Slack invite failed for #{user.email}: #{result[:error]}"
    end
  end

end
