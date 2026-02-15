# frozen_string_literal: true

class SlackService
  class SlackError < StandardError; end
  class ConfigurationError < SlackError; end
  class ApiError < SlackError; end

  def initialize
    @client = build_client
    @user_client = build_user_client
  end

  # Sync PWL ID to Slack profile for existing user
  # Only updates users who are already in Slack - does not invite new users
  def sync_user_to_slack(email:, p_id:)
    raise ConfigurationError, "Slack client not configured" unless configured?
    return unless p_id.present?

    # Find user in Slack
    slack_user = find_user_by_email(email)

    if slack_user
      Rails.logger.info "Found #{email} in Slack workspace, syncing PWL ID"
      update_slack_profile_field(slack_user["id"], p_id)
      { "ok" => true, "synced" => true, "user" => slack_user }
    else
      Rails.logger.info "User #{email} not found in Slack workspace, skipping"
      { "ok" => true, "synced" => false, "message" => "User not in Slack workspace" }
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Slack API error syncing #{email}: #{e.message}"
    raise ApiError, "Slack API error: #{e.message}"
  end

  # Get user info by email
  def find_user_by_email(email)
    raise ConfigurationError, "Slack client not configured" unless configured?

    response = @client.users_lookupByEmail(email: email)

    if response["ok"]
      response["user"]
    else
      nil
    end
  rescue Slack::Web::Api::Errors::UsersNotFound
    nil
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Error looking up Slack user #{email}: #{e.message}"
    nil
  end

  # List all workspace members
  def list_members(limit: 200)
    raise ConfigurationError, "Slack client not configured" unless configured?

    members = []
    cursor = nil
    page_count = 0

    loop do
      page_count += 1
      Rails.logger.info "Fetching Slack members page #{page_count} (cursor: #{cursor.present? ? 'present' : 'nil'})"

      # Don't pass cursor parameter if it's nil (first request)
      response = if cursor.present?
        @client.users_list(limit: limit, cursor: cursor)
      else
        @client.users_list(limit: limit)
      end

      break unless response["ok"]

      page_members = response["members"].reject { |m| m["is_bot"] || m["deleted"] }
      Rails.logger.info "  Found #{page_members.size} active members on page #{page_count}"
      members.concat(page_members)

      # Debug cursor handling
      Rails.logger.info "  Response metadata: #{response['response_metadata'].inspect}"
      cursor = response["response_metadata"]&.dig("next_cursor")
      Rails.logger.info "  Next cursor value: #{cursor.inspect}"
      Rails.logger.info "  Cursor blank?: #{cursor.blank?}, Cursor empty?: #{cursor.to_s.empty?}"

      break if cursor.blank? || cursor.to_s.empty?
    end

    Rails.logger.info "Total Slack members fetched: #{members.size} across #{page_count} pages"
    members
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Error listing Slack members: #{e.message}"
    []
  end

  # Sync Slack users to IDP
  def sync_slack_users_to_idp
    return unless configured?

    members = list_members
    synced_count = 0
    skipped_count = 0

    members.each do |member|
      email = member.dig("profile", "email")
      next if email.blank?

      # Check if user already exists
      user = User.find_by(email: email)

      if user
        # Update Slack ID and profile fields
        profile_attrs = extract_slack_profile_fields(member)

        # Resolve manager relationship from Slack manager ID to IDP user ID
        if profile_attrs[:slack_manager_id].present?
          manager = User.find_by(slack_id: profile_attrs[:slack_manager_id])
          profile_attrs[:manager_id] = manager&.id if manager&.is_manager_or_manageable?
        end

        if user.slack_id.blank? || user.slack_profile_synced_at.nil? || user.slack_profile_synced_at < 1.hour.ago
          user.update!(
            slack_id: member["id"],
            slack_joined_at: Time.zone.at(member["updated"].to_i),
            **profile_attrs,
            slack_profile_synced_at: Time.current
          )
          synced_count += 1
        else
          skipped_count += 1
        end
      else
        # Create new user from Slack member
        create_user_from_slack_member(member)
        synced_count += 1
      end
    rescue => e
      Rails.logger.error "Error syncing Slack user #{email}: #{e.message}"
      next
    end

    Rails.logger.info "Synced #{synced_count} Slack users, skipped #{skipped_count}"
    { synced: synced_count, skipped: skipped_count }
  end

  # Sync IDP users to Slack (profile updates only, no invitations)
  def sync_idp_users_to_slack
    return unless configured?

    synced_count = 0
    skipped_count = 0

    User.find_each do |user|
      # Check if user exists in Slack
      slack_user = find_user_by_email(user.email)

      if slack_user
        # User exists in Slack
        slack_id = slack_user["id"]

        # Update local slack_id if not set
        if user.slack_id.blank?
          user.update(
            slack_id: slack_id,
            slack_joined_at: Time.zone.at(slack_user["updated"].to_i)
          )
        end

        # Sync API-editable fields and PWL ID to Slack
        fields_updated = false

        # Update PWL ID if present
        if user.p_id.present?
          update_slack_profile_field(slack_id, user.p_id)
          fields_updated = true
        end

        # Update other API-editable fields
        if update_slack_api_fields(slack_id, user)
          fields_updated = true
        end

        if fields_updated
          synced_count += 1
        else
          skipped_count += 1
        end
      else
        # User not in Slack workspace yet - skip
        Rails.logger.debug "User #{user.email} not in Slack workspace, skipping"
        skipped_count += 1
      end
    rescue => e
      Rails.logger.error "Error syncing IDP user #{user.email}: #{e.message}"
      next
    end

    Rails.logger.info "Synced #{synced_count} PWL IDs to Slack profiles, skipped #{skipped_count}"
    { synced: synced_count, skipped: skipped_count }
  end

  # Check if Slack is properly configured
  def configured?
    token.present? && team_id.present?
  end

  private

  def build_client
    return nil unless token.present?

    Slack::Web::Client.new(token: token)
  end

  def build_user_client
    return nil unless user_token.present?

    Slack::Web::Client.new(token: user_token)
  end

  def token
    @token ||= ENV["SLACK_BOT_TOKEN"] || Rails.application.credentials.dig(:slack, :bot_token)
  end

  def user_token
    @user_token ||= ENV["SLACK_USER_TOKEN"] || Rails.application.credentials.dig(:slack, :user_token)
  end

  def team_id
    @team_id ||= ENV["SLACK_TEAM_ID"] || Rails.application.credentials.dig(:slack, :team_id)
  end

  def default_channels
    channels = ENV["SLACK_DEFAULT_CHANNELS"] || Rails.application.credentials.dig(:slack, :default_channels)
    channels&.split(",")&.map(&:strip) || []
  end

  # Update Slack custom profile field with PWL ID
  # Uses user token (requires users.profile:write scope)
  def update_slack_profile_field(slack_user_id, p_id)
    return unless slack_user_id.present? && p_id.present?

    unless @user_client
      Rails.logger.warn "Slack user token not configured, cannot update profile fields"
      return
    end

    @user_client.users_profile_set(
      user: slack_user_id,
      profile: {
        fields: {
          "Xf09J13S96F9" => { value: p_id }
        }
      }.to_json
    )

    Rails.logger.info "Updated Slack profile field for user #{slack_user_id} with PWL ID #{p_id}"
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Error updating Slack profile field for #{slack_user_id}: #{e.message}"
  end

  # Update API-editable Slack profile fields from IDP
  # Only pushes fields that are API-editable (not user-editable)
  def update_slack_api_fields(slack_user_id, user)
    return false unless slack_user_id.present?
    return false unless @user_client

    # Build fields hash for API-editable fields only
    fields = {}

    # Field IDs from Slack workspace configuration
    fields["Xf079DHXGT0E"] = { value: user.slack_title } if user.slack_title.present?
    fields["Xf079DHXCTS36"] = { value: user.slack_city } if user.slack_city.present?
    fields["Xf079DHX7D15W"] = { value: user.slack_state } if user.slack_state.present?
    fields["Xf079DHX6AAAF"] = { value: user.slack_country } if user.slack_country.present?
    fields["Xf079BM6AJK7M"] = { value: user.slack_organization } if user.slack_organization.present?
    fields["Xf079EKLUIVZD"] = { value: user.slack_division } if user.slack_division.present?
    fields["Xf079RHARP0NP"] = { value: user.slack_department } if user.slack_department.present?
    fields["Xf079RLV9Y5N"] = { value: user.slack_cost_center } if user.slack_cost_center.present?

    # Convert IDP manager_id to Slack manager_id for push
    if user.manager_id.present? && user.manager&.slack_id.present?
      fields["Xf079DHXFKVR"] = { value: user.manager.slack_id }
    end

    return false if fields.empty?

    @user_client.users_profile_set(
      user: slack_user_id,
      profile: { fields: fields }.to_json
    )

    Rails.logger.info "Updated API-editable fields for user #{slack_user_id}"
    true
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Error updating API fields for #{slack_user_id}: #{e.message}"
    false
  end

  # Extract Slack profile fields from member object
  def extract_slack_profile_fields(member)
    profile = member["profile"]
    fields = profile["fields"] || {}

    {
      # Pull-only fields (user editable in Slack)
      slack_pronouns: profile["pronouns"],
      slack_display_name: profile["display_name"],
      slack_status_text: profile["status_text"],
      slack_status_emoji: profile["status_emoji"],
      slack_phone: profile["phone"],
      slack_role_description: fields.dig("role_description", "value") || fields.dig("Xf079DHXFB7", "value"),
      slack_website: fields.dig("website", "value") || fields.dig("Xf079DHXFB8", "value"),
      slack_github: fields.dig("github", "value") || fields.dig("Xf079DHXFB9", "value"),
      slack_linkedin: fields.dig("linkedin", "value") || fields.dig("Xf079DHXFBA", "value"),
      slack_profile_image_url: profile["image_512"] || profile["image_192"],

      # Push & pull fields (API editable)
      slack_title: profile["title"] || fields.dig("Xf079DHXGT0E", "value"),
      slack_city: fields.dig("Xf079DHXCTS36", "value"),
      slack_state: fields.dig("Xf079DHX7D15W", "value"),
      slack_country: fields.dig("Xf079DHX6AAAF", "value"),
      slack_organization: fields.dig("Xf079BM6AJK7M", "value"),
      slack_division: fields.dig("Xf079EKLUIVZD", "value"),
      slack_department: fields.dig("Xf079RHARP0NP", "value"),
      slack_cost_center: fields.dig("Xf079RLV9Y5N", "value"),
      slack_manager_id: fields.dig("Xf079DHXFKVR", "value")
    }.compact
  end

  def create_user_from_slack_member(member)
    profile = member["profile"]
    email = profile["email"]

    # Parse name from Slack profile
    first_name = profile["first_name"].presence || profile["real_name"]&.split&.first || "NOTSET"
    last_name = profile["last_name"].presence || profile["real_name"]&.split&.drop(1)&.join(" ").presence || "NOTSET"

    # Generate a secure random password
    password = SecureRandom.alphanumeric(20) + "A1!" # Meets complexity requirements

    # Extract all profile fields
    profile_attrs = extract_slack_profile_fields(member)

    # Resolve manager relationship from Slack manager ID to IDP user ID
    if profile_attrs[:slack_manager_id].present?
      manager = User.find_by(slack_id: profile_attrs[:slack_manager_id])
      profile_attrs[:manager_id] = manager&.id if manager&.is_manager_or_manageable?
    end

    user = User.create!(
      email: email,
      first_name: first_name,
      last_name: last_name,
      password: password,
      password_confirmation: password,
      slack_id: member["id"],
      slack_joined_at: Time.zone.at(member["updated"].to_i),
      **profile_attrs,
      slack_profile_synced_at: Time.current
    )

    Rails.logger.info "Created user from Slack member: #{email}"
    user
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create user from Slack member #{email}: #{e.message}"
    raise
  end
end
