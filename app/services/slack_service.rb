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

  # Invite an email address to the Slack workspace.
  #
  # Slack has NO official invite API for non-Enterprise (nonprofit/standard)
  # workspaces, so this hits the undocumented `users.admin.inviteBulk` endpoint on
  # the workspace subdomain, authenticated with a browser session token (xoxc) and
  # the matching `d` cookie (xoxd) captured from a logged-in admin's browser. This
  # is unsupported and fragile: the browser token/cookie expire (roughly on the
  # admin's Slack logout) and Slack can change the endpoint at any time. Failures
  # surface via the returned result rather than raising, except for missing config.
  # (Approach mirrors hackclub/arcadius, which runs this in production.)
  #
  # Returns { ok:, already_member:, error:, raw: } — `ok` true means the invite was
  # sent OR the person is already in / invited to the workspace.
  INVITE_OK_ERRORS = %w[already_in_team already_invited already_in_team_invited_user sent_recently].freeze

  # guest: :single_channel (ultra_restricted, default — one channel until they
  #        accept the code of conduct), :multi_channel (restricted), or :member.
  def invite_to_workspace(email:, real_name: nil, channels: nil, guest: :single_channel)
    raise ConfigurationError, "Slack browser token (SLACK_BROWSER_TOKEN / xoxc) not configured" if browser_token.blank?
    raise ConfigurationError, "Slack cookie (SLACK_COOKIE / xoxd) not configured" if slack_cookie.blank?
    raise ConfigurationError, "Slack team_id not configured" if team_id.blank?
    raise ConfigurationError, "Slack workspace subdomain (SLACK_WORKSPACE_SUBDOMAIN) not configured" if workspace_subdomain.blank?

    restricted = guest == :multi_channel
    ultra_restricted = guest == :single_channel
    invite_type = ultra_restricted ? "ultra_restricted" : (restricted ? "restricted" : "regular")
    # Single-channel guests land in the code-of-conduct channel until they accept.
    channels ||= ultra_restricted ? [coc_channel].compact.presence || default_channels : default_channels

    # Field shape mirrors a real Slack web-client inviteBulk request.
    body = admin_api_post("users.admin.inviteBulk", {
      "invites" => [{ email: email, mode: "manual", type: invite_type }].to_json,
      "team_id" => team_id,
      "restricted" => restricted.to_s,
      "ultra_restricted" => ultra_restricted.to_s,
      "campaign" => "composer",
      "channels" => channels.join(","),
      "_x_reason" => "submit-invite-to-workspace-invites"
    })

    # inviteBulk returns { ok:, invites: [{ email:, ok:, error: }] } — a per-invite
    # failure can sit under a top-level ok:true, so inspect the individual result.
    invite = (body["invites"] || []).first || {}
    error = invite["error"] || body["error"]

    if body["ok"] && invite["ok"] != false && error.nil?
      { ok: true, already_member: false, error: nil, raw: body }
    elsif INVITE_OK_ERRORS.include?(error)
      { ok: true, already_member: true, error: error, raw: body }
    else
      Rails.logger.error "Slack invite failed for #{email}: #{error.inspect}"
      { ok: false, already_member: false, error: error || "unknown_error", raw: body }
    end
  rescue Faraday::Error => e
    Rails.logger.error "Slack invite request error for #{email}: #{e.message}"
    { ok: false, already_member: false, error: "request_failed", raw: nil }
  end

  # Promote a single/multi-channel guest to a full workspace member, via the
  # undocumented `users.admin.setRegular` endpoint (same xoxc/xoxd auth as invite).
  # Used once a guest has accepted the code of conduct. Returns { ok:, error:, raw: }.
  def promote_to_member(slack_user_id)
    body = admin_api_post("users.admin.setRegular", {
      "user" => slack_user_id,
      "team_id" => team_id,
      "_x_reason" => "member-set-regular"
    })

    Rails.logger.error "Slack promote failed for #{slack_user_id}: #{body["error"].inspect}" unless body["ok"]
    { ok: !!body["ok"], error: body["error"], raw: body }
  rescue Faraday::Error => e
    Rails.logger.error "Slack promote request error for #{slack_user_id}: #{e.message}"
    { ok: false, error: "request_failed", raw: nil }
  end

  # DM a newly-joined guest the code of conduct with an "I accept" button. Uses
  # the bot token (needs chat:write + im:write). The button's action_id is
  # "accept_coc" and its value is the Slack user id, handled by the interactions
  # webhook. Returns the Slack API response.
  def post_code_of_conduct(slack_user_id, coc_url: nil)
    raise ConfigurationError, "Slack client not configured" unless @client

    coc_url ||= self.class.code_of_conduct_url
    intro = "Welcome to Patchwork Labs! :wave: Before you get full access to the community, " \
            "please read our Code of Conduct and accept it below."
    coc_line = coc_url.present? ? "Read it here: #{coc_url}" : "Please review our Code of Conduct."

    @client.chat_postMessage(
      channel: slack_user_id,
      text: "Please review and accept the Patchwork Labs Code of Conduct to get full access.",
      blocks: [
        { type: "section", text: { type: "mrkdwn", text: "*#{intro}*\n\n#{coc_line}" } },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              style: "primary",
              text: { type: "plain_text", text: "I accept the Code of Conduct", emoji: true },
              action_id: "accept_coc",
              value: slack_user_id
            }
          ]
        }
      ]
    )
  end

  def self.code_of_conduct_url
    ENV["SLACK_COC_URL"] || Rails.application.credentials.dig(:slack, :coc_url)
  end

  # Get user info by email with full profile including custom fields
  def find_user_by_email(email, include_profile: false)
    raise ConfigurationError, "Slack client not configured" unless configured?

    # First lookup user by email to get their ID
    response = @client.users_lookupByEmail(email: email)

    if response["ok"]
      user = response["user"]

      # If we need full profile with custom fields and have a user token, fetch it
      # Custom profile fields require a user token with users.profile:read scope
      if include_profile && @user_client
        profile_response = @user_client.users_profile_get(user: user["id"])
        if profile_response["ok"]
          # Merge the full profile back into the user object
          user["profile"] = profile_response["profile"]
        end
      end

      user
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

      # Only include full members (not bots, deleted, guests, or deactivated)
      page_members = response["members"].reject do |m|
        m["id"] == "USLACKBOT" ||   # Slackbot (special system account)
        m["is_bot"] ||
        m["deleted"] ||
        m["is_restricted"] ||      # Guest users
        m["is_ultra_restricted"] || # Single-channel guests
        m["profile"]["deactivated"]  # Deactivated accounts
      end
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

      # Fetch full profile with custom fields if user token is available
      if @user_client
        begin
          profile_response = @user_client.users_profile_get(user: member["id"])
          member["profile"] = profile_response["profile"] if profile_response["ok"]
        rescue Slack::Web::Api::Errors::SlackError => e
          Rails.logger.warn "Could not fetch full profile for #{email}: #{e.message}"
        end
      end

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

  # Browser session credentials for the undocumented invite/promote endpoints,
  # captured from a logged-in workspace admin's Slack session.
  def browser_token
    @browser_token ||= ENV["SLACK_BROWSER_TOKEN"] || Rails.application.credentials.dig(:slack, :browser_token)
  end

  def slack_cookie
    @slack_cookie ||= ENV["SLACK_COOKIE"] || Rails.application.credentials.dig(:slack, :cookie)
  end

  # Workspace subdomain, e.g. "patchworklabs" for patchworklabs.slack.com.
  def workspace_subdomain
    @workspace_subdomain ||= ENV["SLACK_WORKSPACE_SUBDOMAIN"] || Rails.application.credentials.dig(:slack, :workspace_subdomain)
  end

  # Channel single-channel guests are invited into (the code-of-conduct channel).
  def coc_channel
    @coc_channel ||= ENV["SLACK_COC_CHANNEL"] || Rails.application.credentials.dig(:slack, :coc_channel)
  end

  # POST to an undocumented workspace-admin endpoint (users.admin.*) the way the
  # real Slack web client does: multipart/form-data body carrying the xoxc token,
  # authenticated with the xoxd `d` cookie. Returns parsed JSON. May raise
  # Faraday::Error (handled by callers) or ConfigurationError (missing creds).
  def admin_api_post(api_method, fields)
    raise ConfigurationError, "Slack browser token (SLACK_BROWSER_TOKEN / xoxc) not configured" if browser_token.blank?
    raise ConfigurationError, "Slack cookie (SLACK_COOKIE / xoxd) not configured" if slack_cookie.blank?
    raise ConfigurationError, "Slack team_id not configured" if team_id.blank?
    raise ConfigurationError, "Slack workspace subdomain (SLACK_WORKSPACE_SUBDOMAIN) not configured" if workspace_subdomain.blank?

    all_fields = {
      "token" => browser_token,
      "_x_mode" => "online",
      "_x_sonic" => "true",
      "_x_app_name" => "client"
    }.merge(fields)

    boundary = "----WeaveFormBoundary#{SecureRandom.hex(10)}"
    body = all_fields.map do |name, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
    end.join + "--#{boundary}--\r\n"

    response = Faraday.post("https://#{workspace_subdomain}.slack.com/api/#{api_method}") do |req|
      req.headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.headers["Cookie"] = "d=#{cookie_for_header};"
      req.body = body
    end

    JSON.parse(response.body.presence || "{}")
  end

  # The Slack `d` cookie is transmitted URL-encoded by the browser. DevTools often
  # shows the decoded value (raw +/ from its base64), so re-encode when a decoded
  # value was stored; leave an already-encoded value (containing %) untouched.
  def cookie_for_header
    c = slack_cookie.to_s
    return c if c.blank? || c.include?("%")

    c.start_with?("xoxd-") ? "xoxd-#{CGI.escape(c.delete_prefix('xoxd-'))}" : CGI.escape(c)
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
    fields["Xf0794EQ8TQE"] = { value: user.slack_title } if user.slack_title.present?
    fields["Xf078WGTT53R"] = { value: user.slack_city } if user.slack_city.present?
    fields["Xf079ZT2R5DW"] = { value: user.slack_state } if user.slack_state.present?
    fields["Xf079B0K3ASF"] = { value: user.slack_country } if user.slack_country.present?
    fields["Xf079B0K367M"] = { value: user.slack_organization } if user.slack_organization.present?
    fields["Xf079PPEUW2D"] = { value: user.slack_division } if user.slack_division.present?
    fields["Xf07986PJQPP"] = { value: user.slack_department } if user.slack_department.present?
    fields["Xf079B3V5734"] = { value: user.slack_cost_center } if user.slack_cost_center.present?

    # Convert IDP manager_id to Slack manager_id for push
    if user.manager_id.present? && user.manager&.slack_id.present?
      fields["Xf07986PJV2R"] = { value: user.manager.slack_id }
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
      slack_role_description: fields.dig("Xf09E7DJ7Y1Y", "value"),
      slack_website: fields.dig("Xf07CK5ZT401", "value"),
      slack_github: fields.dig("Xf09JVCPFL4R", "value"),
      slack_linkedin: fields.dig("Xf09J13F51KR", "value"),
      slack_profile_image_url: profile["image_512"] || profile["image_192"],

      # Push & pull fields (API editable)
      slack_title: profile["title"],
      slack_city: fields.dig("Xf078WGTT53R", "value"),
      slack_state: fields.dig("Xf079ZT2R5DW", "value"),
      slack_country: fields.dig("Xf079B0K3ASF", "value"),
      slack_organization: fields.dig("Xf079B0K367M", "value"),
      slack_division: fields.dig("Xf079PPEUW2D", "value"),
      slack_department: fields.dig("Xf07986PJQPP", "value"),
      slack_cost_center: fields.dig("Xf079B3V5734", "value"),
      slack_manager_id: fields.dig("Xf07986PJV2R", "value")
    }.compact
  end

  def create_user_from_slack_member(member)
    # Fetch full profile with custom fields if user token is available
    if @user_client
      begin
        profile_response = @user_client.users_profile_get(user: member["id"])
        member["profile"] = profile_response["profile"] if profile_response["ok"]
      rescue Slack::Web::Api::Errors::SlackError => e
        Rails.logger.warn "Could not fetch full profile for #{member['id']}: #{e.message}"
      end
    end

    profile = member["profile"]
    email = profile["email"]

    # Parse name from Slack profile
    first_name = profile["first_name"].presence || profile["real_name"]&.split&.first || "NOTSET"
    last_name = profile["last_name"].presence || profile["real_name"]&.split&.drop(1)&.join(" ").presence || "NOTSET"

    # Generate a secure random password that satisfies the password policy
    password = User.generate_secure_password

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
