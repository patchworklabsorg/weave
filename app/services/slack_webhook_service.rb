# frozen_string_literal: true

class SlackWebhookService
  class << self
    # Process team_join event - new user joined Slack
    def process_team_join(slack_user_data)
      # Skip bots and deleted users
      return if slack_user_data['is_bot'] || slack_user_data['deleted']

      email = slack_user_data.dig('profile', 'email')
      slack_id = slack_user_data['id']

      unless email.present?
        Rails.logger.warn "[SlackWebhookService] No email for Slack user #{slack_id}"
        return
      end

      # Check if user already exists in IDP
      user = User.find_by(email: email.downcase)

      if user
        # Update existing user with Slack info
        user.update!(
          slack_id: slack_id,
          slack_joined_at: Time.current
        )
        Rails.logger.info "[SlackWebhookService] Updated existing user #{user.id} with Slack ID #{slack_id}"
      else
        # Create new IDP user from Slack member
        user = create_user_from_slack_member(slack_user_data)
        Rails.logger.info "[SlackWebhookService] Created new user #{user.id} from Slack member #{slack_id}"
      end

      user
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[SlackWebhookService] Validation error creating/updating user: #{e.message}"
      raise
    rescue => e
      Rails.logger.error "[SlackWebhookService] Error processing team_join: #{e.message}"
      raise
    end

    # Process user_change event - user profile updated in Slack
    def process_user_change(slack_user_data)
      # Skip bots and deleted users
      return if slack_user_data['is_bot'] || slack_user_data['deleted']

      slack_id = slack_user_data['id']
      user = User.find_by(slack_id: slack_id)

      unless user
        Rails.logger.warn "[SlackWebhookService] No IDP user found for Slack ID #{slack_id}"
        return
      end

      # Extract updated profile data
      profile = slack_user_data['profile']
      updates = {}

      # Update email if changed. A Slack-driven email change must NOT silently
      # become a verified login identifier: clear the confirmation so the new
      # address has to be re-confirmed before it can be used to log in.
      if profile['email'].present? && profile['email'].downcase != user.email
        updates[:email] = profile['email'].downcase
        updates[:email_confirmed_at] = nil
      end

      # Update name if changed
      first_name = profile['first_name'] || profile['real_name']&.split(' ')&.first
      last_name = profile['last_name'] || profile['real_name']&.split(' ')&.drop(1)&.join(' ')

      if first_name.present? && first_name != user.first_name
        updates[:first_name] = first_name
      end

      if last_name.present? && last_name != user.last_name
        updates[:last_name] = last_name
      end

      # Apply updates if any
      if updates.any?
        user.update!(updates)
        Rails.logger.info "[SlackWebhookService] Updated user #{user.id} with changes: #{updates.keys.join(', ')}"
      else
        Rails.logger.debug "[SlackWebhookService] No changes for user #{user.id}"
      end

      user
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[SlackWebhookService] Validation error updating user: #{e.message}"
      raise
    rescue => e
      Rails.logger.error "[SlackWebhookService] Error processing user_change: #{e.message}"
      raise
    end

    private

    # Create new IDP user from Slack member data
    # Reuses pattern from SlackService
    def create_user_from_slack_member(member)
      profile = member['profile']
      email = profile['email']&.downcase

      # Extract name components
      first_name = profile['first_name'] || profile['real_name']&.split(' ')&.first || 'Unknown'
      last_name = profile['last_name'] || profile['real_name']&.split(' ')&.drop(1)&.join(' ') || 'User'

      # Create user with Slack info
      user = User.new(
        email: email,
        first_name: first_name,
        last_name: last_name,
        slack_id: member['id'],
        slack_joined_at: Time.current,
        password: User.generate_secure_password # Random password - user logs in via magic link
      )

      # Skip email confirmation if using Devise confirmable
      if user.respond_to?(:skip_confirmation!)
        user.skip_confirmation!
      end

      user.save!
      user
    end
  end
end
