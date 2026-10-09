# frozen_string_literal: true

class SlackService
  class SlackError < StandardError; end
  class ConfigurationError < SlackError; end
  class ApiError < SlackError; end

  # Standard Slack profile keys, read from users.list and users.profile.get.
  STANDARD_PROFILE_FIELDS = {
    slack_display_name: "display_name",
    slack_status_text: "status_text",
    slack_status_emoji: "status_emoji",
    slack_phone: "phone",
    slack_title: "title"
  }.freeze

  # Custom profile fields, by their label in the Slack workspace. Field IDs
  # differ between workspaces (production and the staging test workspace), so
  # #custom_field_ids looks them up by label. Only users.profile.get returns
  # custom field values, so they are read only from it.
  PULL_ONLY_CUSTOM_FIELDS = {
    slack_role_description: "Role Description",
    slack_website: "Personal Website",
    slack_github: "Github",
    slack_linkedin: "Linkedin"
  }.freeze

  # Custom fields that Weave admins can edit too (see #push_profile_fields).
  SHARED_CUSTOM_FIELDS = {
    slack_city: "City",
    slack_state: "State",
    slack_country: "Country",
    slack_organization: "Organization",
    slack_division: "Division",
    slack_department: "Department",
    slack_cost_center: "Cost Center"
  }.freeze

  MANAGER_FIELD = "Manager"
  PWL_ID_FIELD = "pwl_idp_id"

  # callback_id of the code-of-conduct form (see #open_code_of_conduct_form).
  CODE_OF_CONDUCT_FORM = "coc_form"

  # How long a workspace's label -> field ID map is cached.
  CUSTOM_FIELD_IDS_TTL = 1.hour

  # Weave attributes that #push_profile_fields sends to Slack.
  PUSHED_ATTRIBUTES = ["slack_title", "manager_id", *SHARED_CUSTOM_FIELDS.keys.map(&:to_s)].freeze

  def initialize
    @client = build_client
    @user_client = build_user_client
  end

  # Sync PWL ID to Slack profile for existing user
  # Only updates users who are already in Slack - does not invite new users
  def sync_user_to_slack(email:, p_id:)
    raise ConfigurationError, "Slack client not configured" unless configured?
    return if p_id.blank?

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
    invite_type = if ultra_restricted
                    "ultra_restricted"
                  else
                    (restricted ? "restricted" : "regular")
                  end
    # Single-channel guests land in the code-of-conduct channel until they accept.
    channels ||= ultra_restricted ? [coc_channel].compact.presence || default_channels : default_channels

    # Field shape mirrors a real Slack web-client inviteBulk request.
    body = admin_api_post("users.admin.inviteBulk", {
                            "invites"          => [{ email: email, mode: "manual", type: invite_type }].to_json,
                            "team_id"          => team_id,
                            "restricted"       => restricted.to_s,
                            "ultra_restricted" => ultra_restricted.to_s,
                            "campaign"         => "composer",
                            "channels"         => channels.join(","),
                            "_x_reason"        => "submit-invite-to-workspace-invites"
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
                            "user"      => slack_user_id,
                            "team_id"   => team_id,
                            "_x_reason" => "member-set-regular"
                          })

    Rails.logger.error "Slack promote failed for #{slack_user_id}: #{body["error"].inspect}" unless body["ok"]
    { ok: !!body["ok"], error: body["error"], raw: body }
  rescue Faraday::Error => e
    Rails.logger.error "Slack promote request error for #{slack_user_id}: #{e.message}"
    { ok: false, error: "request_failed", raw: nil }
  end

  # DM someone the code of conduct with a button to accept it. Uses the bot
  # token (needs chat:write + im:write). Returns the Slack API response.
  #
  # intro is the opening text (mrkdwn). It defaults to the welcome for a
  # newly-joined guest. CodeOfConductRequestJob passes its own.
  #
  # With collect_name: false, the button accepts at once: its action_id is
  # "accept_coc" and its value is the Slack user id. With collect_name: true
  # (for people whose name the Slack import could not find), the button
  # ("open_coc_form") opens a form that asks for their name and then accepts
  # (see #open_code_of_conduct_form). The interactions webhook handles both.
  def post_code_of_conduct(slack_user_id, coc_url: nil, intro: nil, collect_name: false)
    raise ConfigurationError, "Slack client not configured" unless @client

    coc_url ||= self.class.code_of_conduct_url
    intro ||= "*Welcome to Patchwork Labs! :wave: Before you get full access to the community, " \
              "please read our Code of Conduct and accept it below.*"
    coc_line = coc_url.present? ? "Read it here: #{coc_url}" : "Please review our Code of Conduct."

    button = if collect_name
               { text: "Review and accept", action_id: "open_coc_form" }
             else
               { text: "I accept the Code of Conduct", action_id: "accept_coc" }
             end

    @client.chat_postMessage(
      channel: slack_user_id,
      text: "Please review and accept the Patchwork Labs Code of Conduct.",
      blocks: [
        { type: "section", text: { type: "mrkdwn", text: "#{intro}\n\n#{coc_line}" } },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              style: "primary",
              text: { type: "plain_text", text: button[:text], emoji: true },
              action_id: button[:action_id],
              value: slack_user_id
            }
          ]
        }
      ]
    )
  end

  # Opens the code-of-conduct form from a button click. trigger_id comes from
  # the click and expires after 3 seconds, so call this while answering it.
  #
  # The form asks for a first and last name when the user's name is missing
  # (or when there is no linked user, since nothing is known about them).
  # message is the DM the button was in, as { channel:, ts: }. It goes into
  # private_metadata, so the submission can replace the DM.
  def open_code_of_conduct_form(trigger_id:, user:, message: nil)
    raise ConfigurationError, "Slack client not configured" unless @client

    coc_url = self.class.code_of_conduct_url
    coc_text = coc_url.present? ? "<#{coc_url}|Read the Code of Conduct>" : "Please review our Code of Conduct."
    blocks = [
      { type: "section", text: { type: "mrkdwn", text: "#{coc_text}, then choose *I accept* below." } }
    ]
    if user.nil? || user.name_missing?
      blocks.unshift({ type: "section", text: { type: "mrkdwn", text: "We don't have your name yet. Please add it." } })
      blocks.insert(1, name_input("first_name", "First name"), name_input("last_name", "Last name"))
    end

    @client.views_open(
      trigger_id: trigger_id,
      view: {
        type: "modal",
        callback_id: CODE_OF_CONDUCT_FORM,
        private_metadata: (message || {}).to_json,
        title: { type: "plain_text", text: "Code of Conduct" },
        submit: { type: "plain_text", text: "I accept" },
        close: { type: "plain_text", text: "Not now" },
        blocks: blocks
      }
    )
  end

  # Replaces a code-of-conduct DM with a thank-you, so its button can't be
  # used again.
  def mark_code_of_conduct_accepted(channel:, ts:, already_member: false)
    raise ConfigurationError, "Slack client not configured" unless @client

    @client.chat_update(channel: channel, ts: ts, text: self.class.code_of_conduct_thanks(already_member:), blocks: [])
  end

  def self.code_of_conduct_thanks(already_member:)
    if already_member
      ":white_check_mark: Thanks for accepting the Code of Conduct! :tada:"
    else
      ":white_check_mark: Thanks for accepting the Code of Conduct — you now have full access to the Patchwork Labs Slack. Welcome! :tada:"
    end
  end

  # Where members open the workspace, e.g. https://patchworklabs.slack.com.
  # nil when the subdomain is not configured.
  def self.workspace_url
    subdomain = ENV["SLACK_WORKSPACE_SUBDOMAIN"] || Rails.application.credentials.dig(:slack, :workspace_subdomain)
    "https://#{subdomain}.slack.com" if subdomain.present?
  end

  def self.code_of_conduct_url
    ENV["SLACK_COC_URL"] || Rails.application.credentials.dig(:slack, :coc_url)
  end

  # The email address of a Slack user, from users.info (needs users:read.email).
  # Events API payloads (team_join, user_change) leave profile.email out, so
  # webhook handlers look it up here. nil when Slack does not return one.
  def find_email(slack_user_id)
    raise ConfigurationError, "Slack client not configured" unless @client

    response = @client.users_info(user: slack_user_id)
    response.dig("user", "profile", "email").presence if response["ok"]
  rescue Slack::Web::Api::Errors::UserNotFound
    nil
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Slack API error looking up email for #{slack_user_id}: #{e.message}"
    raise ApiError, "Slack API error: #{e.message}"
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
        m["id"] == "USLACKBOT" || # Slackbot (special system account)
          m["is_bot"] ||
          m["deleted"] ||
          m["is_restricted"] || # Guest users
          m["is_ultra_restricted"] || # Single-channel guests
          m["profile"]["deactivated"] # Deactivated accounts
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
      full_profile = false
      if @user_client
        begin
          profile_response = @user_client.users_profile_get(user: member["id"])
          if profile_response["ok"]
            fetched_profile = profile_response["profile"]
            # users.profile.get omits the email field, so preserve the address
            # we already resolved from users.list — otherwise the profile swap
            # would blank it out and user creation fails validation.
            fetched_profile["email"] = email if fetched_profile["email"].blank?
            member["profile"] = fetched_profile
            full_profile = true
          end
        rescue Slack::Web::Api::Errors::SlackError => e
          Rails.logger.warn "Could not fetch full profile for #{email}: #{e.message}"
        end
      end

      # Check if user already exists (their Slack email may be a confirmed
      # secondary address rather than their Weave primary)
      user = User.find_for_any_email(email)

      if user
        # Slack is the source of truth for profile fields, so a field cleared
        # in Slack is cleared here too. Every member is read on every run: a
        # skipped member would keep old values, and those used to be pushed
        # back over newer Slack edits.
        profile_attrs = extract_slack_profile_fields(member, full_profile: full_profile)
        profile_attrs.merge!(manager_attrs_from_slack(user, profile_attrs[:slack_manager_id], full_profile))

        # list_members returns full members only, so everyone here is one.
        just_linked = user.slack_id.blank?
        user.assign_attributes(slack_id: member["id"], slack_membership: "member", **profile_attrs)
        user.slack_joined_at ||= Time.zone.at(member["updated"].to_i)
        changed = user.changed?
        user.slack_profile_synced_at = Time.current
        user.save!
        changed ? synced_count += 1 : skipped_count += 1
        # On first link Weave's pronouns win if it has any (the push sends them).
        user.apply_slack_pronouns!(member.dig("profile", "pronouns"), just_linked: just_linked)
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
        user.apply_slack_membership!(slack_user)

        # Only the PWL ID is pushed here. Profile fields go to Slack when an
        # admin edits them (PushSlackProfileFieldsJob). Pushing them on every
        # run would write old Weave values over newer Slack edits.
        if user.p_id.present?
          update_slack_profile_field(slack_id, user.p_id)
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

  # Set the standard Slack pronouns field. A blank value clears it.
  # Uses user token (requires users.profile:write scope)
  # Returns false when there is nothing to do (no Slack ID or no user token).
  # Slack errors are raised, so PushPronounsToSlackJob can retry them.
  def update_slack_pronouns(slack_user_id, pronouns)
    return false if slack_user_id.blank?

    unless @user_client
      Rails.logger.warn "Slack user token not configured, cannot update pronouns"
      return false
    end

    @user_client.users_profile_set(
      user: slack_user_id,
      profile: { pronouns: pronouns.to_s }.to_json
    )

    Rails.logger.info "Updated Slack pronouns for user #{slack_user_id}"
    true
  rescue Slack::Web::Api::Errors::SlackError, Slack::Web::Api::Errors::TooManyRequestsError => e
    Rails.logger.error "Error updating Slack pronouns for #{slack_user_id}: #{e.message}"
    raise
  end

  # Push the profile fields Weave admins can edit to Slack. Every field is
  # sent, and a blank value clears it in Slack. A manager with no Slack
  # account is left out, because Slack cannot show it.
  # Uses user token (requires users.profile:write scope)
  # Returns false when there is nothing to do (no Slack ID or no user token).
  # Slack errors are raised, so PushSlackProfileFieldsJob can retry them.
  def push_profile_fields(slack_user_id, user)
    return false if slack_user_id.blank?

    unless @user_client
      Rails.logger.warn "Slack user token not configured, cannot update profile fields"
      return false
    end

    # Without the field IDs, pushing would send only the title and report
    # success. Raise instead, so PushSlackProfileFieldsJob retries.
    raise ApiError, "Could not read the Slack profile fields" unless custom_field_ids

    fields = custom_field_ids_for(SHARED_CUSTOM_FIELDS).to_h { |attr, field_id| [field_id, { value: user.public_send(attr).to_s }] }
    manager = user.manager
    if (manager_field_id = custom_field_id(MANAGER_FIELD))
      if manager.nil?
        fields[manager_field_id] = { value: "" }
      elsif manager.slack_id.present?
        fields[manager_field_id] = { value: manager.slack_id }
      end
    end

    @user_client.users_profile_set(
      user: slack_user_id,
      profile: { title: user.slack_title.to_s, fields: fields }.to_json
    )

    Rails.logger.info "Updated Slack profile fields for user #{slack_user_id}"
    true
  rescue Slack::Web::Api::Errors::SlackError, Slack::Web::Api::Errors::TooManyRequestsError => e
    Rails.logger.error "Error updating Slack profile fields for #{slack_user_id}: #{e.message}"
    raise
  end

  private

  def build_client
    return nil if token.blank?

    Slack::Web::Client.new(token: token)
  end

  def build_user_client
    return nil if user_token.blank?

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

  def name_input(block_id, label)
    {
      type: "input",
      block_id: block_id,
      label: { type: "plain_text", text: label },
      element: { type: "plain_text_input", action_id: "value", max_length: 100 }
    }
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
      "token"       => browser_token,
      "_x_mode"     => "online",
      "_x_sonic"    => "true",
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

    field_id = custom_field_id(PWL_ID_FIELD)
    unless field_id
      Rails.logger.warn "Slack workspace has no \"#{PWL_ID_FIELD}\" profile field, cannot sync PWL ID"
      return
    end

    @user_client.users_profile_set(
      user: slack_user_id,
      profile: { fields: { field_id => { value: p_id } } }.to_json
    )

    Rails.logger.info "Updated Slack profile field for user #{slack_user_id} with PWL ID #{p_id}"
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Error updating Slack profile field for #{slack_user_id}: #{e.message}"
  end

  # Label -> field ID for this workspace's custom profile fields, from
  # team.profile.get (user token, users.profile:read). Labels match without
  # regard to case. Cached for CUSTOM_FIELD_IDS_TTL. nil when the lookup
  # fails; a failure is not cached.
  def custom_field_ids
    @custom_field_ids ||= Rails.cache.fetch(["slack/custom_field_ids", team_id], expires_in: CUSTOM_FIELD_IDS_TTL, skip_nil: true) do
      fetch_custom_field_ids
    end
  end

  def fetch_custom_field_ids
    return unless @user_client

    response = @user_client.team_profile_get
    ids = Array(response.dig("profile", "fields")).to_h { |field| [field["label"].to_s.strip.downcase, field["id"]] }

    expected = [*PULL_ONLY_CUSTOM_FIELDS.values, *SHARED_CUSTOM_FIELDS.values, MANAGER_FIELD, PWL_ID_FIELD]
    missing = expected.reject { |label| ids.key?(label.downcase) }
    Rails.logger.warn "Slack workspace has no profile field for: #{missing.join(', ')}" if missing.any?

    ids
  rescue Slack::Web::Api::Errors::SlackError, Slack::Web::Api::Errors::TooManyRequestsError => e
    Rails.logger.error "Error reading Slack profile fields: #{e.message}"
    nil
  end

  def custom_field_id(label)
    custom_field_ids&.[](label.downcase)
  end

  # attr => field ID for the labels in labels_by_attr that this workspace has.
  def custom_field_ids_for(labels_by_attr)
    labels_by_attr.filter_map { |attr, label| (field_id = custom_field_id(label)) && [attr, field_id] }.to_h
  end

  # Map Slack profile values to Weave attributes. Blank values become nil, so
  # a field cleared in Slack clears Weave too. Custom fields are only read
  # when full_profile is true (users.profile.get succeeded): users.list leaves
  # them out, and reading them from it would clear every one.
  def extract_slack_profile_fields(member, full_profile: false)
    profile = member["profile"]
    attrs = {}

    STANDARD_PROFILE_FIELDS.each do |attr, key|
      attrs[attr] = profile[key].presence if profile.key?(key)
    end

    image_url = profile["image_512"].presence || profile["image_192"].presence
    attrs[:slack_profile_image_url] = image_url if image_url

    # Only fields this workspace has are read. A missing field, or a failed
    # lookup, leaves the Weave value alone instead of clearing it.
    if full_profile && custom_field_ids
      # Slack sends an empty array, not a hash, when no custom field is set.
      fields = profile["fields"].is_a?(Hash) ? profile["fields"] : {}
      labels = PULL_ONLY_CUSTOM_FIELDS.merge(SHARED_CUSTOM_FIELDS, slack_manager_id: MANAGER_FIELD)
      custom_field_ids_for(labels).each do |attr, field_id|
        attrs[attr] = fields.dig(field_id, "value").presence
      end
    end

    attrs
  end

  # Resolve the Slack manager field to a Weave manager_id. An empty Slack
  # field clears a manager that Slack can show (one with a Slack account). A
  # manager without a Slack account exists only in Weave, so Slack cannot
  # clear it.
  def manager_attrs_from_slack(user, slack_manager_id, full_profile)
    if slack_manager_id.present?
      manager = User.find_by(slack_id: slack_manager_id)
      manager&.is_manager_or_manageable? ? { manager_id: manager.id } : {}
    elsif full_profile && user&.manager&.slack_id.present?
      { manager_id: nil }
    else
      {}
    end
  end

  def create_user_from_slack_member(member)
    # Email is only present on the users.list payload; the users.profile.get
    # refetch below omits it, so capture it before the profile is replaced.
    email = member.dig("profile", "email")

    # Fetch full profile with custom fields if user token is available
    full_profile = false
    if @user_client
      begin
        profile_response = @user_client.users_profile_get(user: member["id"])
        if profile_response["ok"]
          member["profile"] = profile_response["profile"]
          full_profile = true
        end
      rescue Slack::Web::Api::Errors::SlackError => e
        Rails.logger.warn "Could not fetch full profile for #{member['id']}: #{e.message}"
      end
    end

    profile = member["profile"]

    # Parse name from Slack profile
    first_name = profile["first_name"].presence || profile["real_name"]&.split&.first || "NOTSET"
    last_name = profile["last_name"].presence || profile["real_name"]&.split&.drop(1)&.join(" ").presence || "NOTSET"

    # Generate a secure random password that satisfies the password policy
    password = User.generate_secure_password

    # Extract all profile fields
    profile_attrs = extract_slack_profile_fields(member, full_profile: full_profile)
    profile_attrs.merge!(manager_attrs_from_slack(nil, profile_attrs[:slack_manager_id], full_profile))

    user = User.create!(
      email: email,
      first_name: first_name,
      last_name: last_name,
      password: password,
      password_confirmation: password,
      slack_id: member["id"],
      slack_joined_at: Time.zone.at(member["updated"].to_i),
      slack_membership: User.slack_membership_for(member),
      pronouns: User.pronouns_from_slack(member.dig("profile", "pronouns")),
      slack_pronouns: User.pronouns_from_slack(member.dig("profile", "pronouns")),
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
