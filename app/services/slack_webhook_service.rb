# frozen_string_literal: true

class SlackWebhookService
  class << self
    # Process team_join event - new user joined Slack
    def process_team_join(slack_user_data)
      # Skip bots and deleted users
      return if slack_user_data["is_bot"] || slack_user_data["deleted"]

      email = slack_user_data.dig("profile", "email")
      slack_id = slack_user_data["id"]

      if email.blank?
        Rails.logger.warn "[SlackWebhookService] No email for Slack user #{slack_id}"
        return
      end

      # Check if user already exists in IDP
      user = User.find_for_any_email(email)

      if user
        # Update existing user with Slack info
        user.update!(
          slack_id: slack_id,
          slack_joined_at: Time.current,
          slack_membership: User.slack_membership_for(slack_user_data)
        )
        Rails.logger.info "[SlackWebhookService] Updated existing user #{user.id} with Slack ID #{slack_id}"
      else
        # Create new IDP user from Slack member
        user = create_user_from_slack_member(slack_user_data)
        Rails.logger.info "[SlackWebhookService] Created new user #{user.id} from Slack member #{slack_id}"
      end

      # New joiners come in as single-channel guests; DM them the code of conduct
      # so they can accept it and be promoted to full member.
      send_code_of_conduct(user)

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
      return if slack_user_data["is_bot"]

      slack_id = slack_user_data["id"]
      user = User.find_by(slack_id: slack_id)

      unless user
        Rails.logger.warn "[SlackWebhookService] No IDP user found for Slack ID #{slack_id}"
        return
      end

      # Slack sends user_change when a guest is promoted to member, when a
      # member is made a guest, and when an account is deactivated. Record the
      # membership before the deactivated check below, so a deactivated account
      # stops being a member.
      user.apply_slack_membership!(slack_user_data)
      return if slack_user_data["deleted"]

      # Extract updated profile data
      profile = slack_user_data["profile"]
      updates = {}


      # Update name if changed
      first_name = profile["first_name"] || profile["real_name"]&.split(" ")&.first
      last_name = profile["last_name"] || profile["real_name"]&.split(" ")&.drop(1)&.join(" ")

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

      add_slack_email_address(user, profile["email"])

      user
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[SlackWebhookService] Validation error updating user: #{e.message}"
      raise
    rescue => e
      Rails.logger.error "[SlackWebhookService] Error processing user_change: #{e.message}"
      raise
    end

    private

    # Slack never changes users.email, because magic links go to that address.
    # Anyone who can edit a Slack profile (a Slack admin, for example) could
    # otherwise redirect the user's sign-in. A new Slack email is added as an
    # unconfirmed secondary address instead, and a confirmation email goes to
    # it. After the user confirms it, they can make it primary themselves. A
    # notice also goes to the primary address, so the user finds out if someone
    # else changed their Slack profile.
    def add_slack_email_address(user, slack_email)
      email = slack_email.to_s.strip.downcase
      return if email.blank? || email == user.email
      return if user.email_addresses.exists?(email: email)

      address = user.email_addresses.new(email: email)
      unless address.save
        Rails.logger.warn "[SlackWebhookService] Did not add Slack email for user #{user.id}: #{address.errors.full_messages.join(', ')}"
        return
      end

      address.send_confirmation_email
      UserMailer.slack_email_address_added(address).deliver_later
      Rails.logger.info "[SlackWebhookService] Added unconfirmed Slack email address #{address.id} for user #{user.id}"
    end

    # DM the code of conduct to a freshly-joined guest (idempotent-ish: skips if
    # they've already accepted). Never lets a Slack failure break webhook handling.
    def send_code_of_conduct(user)
      return if user&.slack_id.blank?
      return if user.slack_coc_accepted_at.present?

      SlackService.new.post_code_of_conduct(user.slack_id)
    rescue => e
      Rails.logger.error "[SlackWebhookService] Failed to post CoC to #{user&.slack_id}: #{e.message}"
    end

    # Create new IDP user from Slack member data
    # Reuses pattern from SlackService
    def create_user_from_slack_member(member)
      profile = member["profile"]
      email = profile["email"]&.downcase

      # Extract name components
      first_name = profile["first_name"] || profile["real_name"]&.split(" ")&.first || "Unknown"
      last_name = profile["last_name"] || profile["real_name"]&.split(" ")&.drop(1)&.join(" ") || "User"

      # Create user with Slack info
      user = User.new(
        email: email,
        first_name: first_name,
        last_name: last_name,
        slack_id: member["id"],
        slack_joined_at: Time.current,
        slack_membership: User.slack_membership_for(member),
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
