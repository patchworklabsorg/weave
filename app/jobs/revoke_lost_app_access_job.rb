# frozen_string_literal: true

# Revokes the OAuth tokens and unredeemed codes of users who may no longer use
# an app (see AppAccess).
#
# The token, userinfo and introspection endpoints already refuse such tokens,
# so this job is cleanup, not the line of defense: it makes the tokens show as
# revoked everywhere and stops them being counted as live sessions.
#
# Pass `user_id` after a user loses a membership, or `application_id` after an
# app loses a grant or becomes restricted. The job checks access again for
# every user and app pair that still has live tokens, so it revokes only what
# the user really lost, and a second run does nothing.
class RevokeLostAppAccessJob < ApplicationJob
  queue_as :default

  def perform(user_id: nil, application_id: nil)
    raise ArgumentError, "pass user_id or application_id" if user_id.nil? && application_id.nil?

    live_pairs(user_id:, application_id:).each do |owner_id, app_id|
      user = User.find_by(id: owner_id)
      application = Doorkeeper::Application.find_by(id: app_id)
      next if user.nil? || application.nil?
      next if AppAccess.permitted?(user, application)

      revoke(owner_id, app_id)
    end
  end

  private

  def live_pairs(user_id:, application_id:)
    [Doorkeeper::AccessToken, Doorkeeper::AccessGrant].flat_map do |model|
      scope = model.where(revoked_at: nil).where.not(resource_owner_id: nil)
      scope = scope.where(resource_owner_id: user_id) if user_id
      scope = scope.where(application_id: application_id) if application_id
      scope.distinct.pluck(:resource_owner_id, :application_id)
    end.uniq
  end

  def revoke(owner_id, app_id)
    now = Time.current
    [Doorkeeper::AccessToken, Doorkeeper::AccessGrant].each do |model|
      model.where(resource_owner_id: owner_id, application_id: app_id, revoked_at: nil)
           .update_all(revoked_at: now) # rubocop:disable Rails/SkipsModelValidations
    end
    Rails.logger.info("Revoked OAuth access after access loss: user_id=#{owner_id} application_id=#{app_id}")
  end

end
