# frozen_string_literal: true

# Member data export (takeout, proposal section 06). The member asks on
# /profile/export, BuildTakeoutJob writes one JSON file with every exportable
# category of DataCategories, and the member gets an email with a link to
# download it after they sign in.
#
# Not in the export, by design:
# - demographics: the vault has no read path for one member, not even the
#   member (see DemographicsVault).
# - raw ID images: they sit behind break-glass and are deleted days after a
#   pass.
# - the Knot: one-way hashes that identify nobody.
# - the internal trust score: staff only, never shown to the member.
module Takeout
  FORMAT_VERSION = 1

  Result = Data.define(:request, :errors) do
    def success? = errors.empty?
  end

  class << self
    # Starts an export. One at a time, and not more often than
    # takeout.cooldown_hours.
    def request!(user)
      if user.takeout_requests.exists?(status: "pending")
        return Result.new(request: nil, errors: { base: I18n.t("data_handling.takeout.errors.pending") })
      end

      last = user.takeout_requests.where(status: %w[ready expired]).maximum(:created_at)
      if last && last > DataRetention.takeout_cooldown.ago
        return Result.new(request: nil, errors: { base: I18n.t("data_handling.takeout.errors.cooldown") })
      end

      request = user.takeout_requests.create!(status: "pending")
      BuildTakeoutJob.perform_later(request.id)
      Result.new(request:, errors: {})
    end

    # Builds the file, attaches it and emails the member.
    def deliver!(request)
      return unless request.pending?

      json = JSON.pretty_generate(build(request.user))
      request.archive.attach(io: StringIO.new(json), filename: "weave-export-#{Date.current.iso8601}.json",
                             content_type: "application/json")
      request.update!(status: "ready", ready_at: Time.current, expires_at: DataRetention.takeout_download_window.from_now)
      DataHandlingMailer.takeout_ready(request).deliver_later
    rescue
      request.update!(status: "failed")
      raise
    end

    # Every exportable category, keyed by category. Read from the registry,
    # so a new exportable category needs an exporter here.
    def build(user)
      {
        "format_version" => FORMAT_VERSION,
        "generated_at"   => Time.current.iso8601,
        "weave_id"       => user.p_id,
        "data_page"      => Weave.data_page_url,
        "categories"     => DataCategories.exportable.to_h do |category|
          [category.key, { "name" => category.name, "data" => export(category.key, user) }]
        end,
        "not_included"   => DataCategories.all.reject(&:exportable).to_h do |category|
          [category.key, I18n.t("data_categories.#{category.key}.not_exported")]
        end
      }
    end

    private

    def export(key, user)
      case key
      when "account_profile" then account_profile(user)
      when "guardian_contact" then guardian_contact(user)
      when "verification_audit" then verification_audit(user)
      when "financial" then financial(user)
      when "participation" then participations(user).reject(&:individual_record_window).map { |row| participation(row) }
      when "funder_records" then participations(user).select(&:individual_record_window).map { |row| participation(row) }
      else raise KeyError, "No exporter for the data category #{key}"
      end
    end

    PROFILE_FIELDS = %w[p_id first_name last_name legal_first_name legal_last_name email pronouns phone_number birthday
                        created_at email_confirmed_at slack_id slack_display_name slack_title slack_pronouns slack_phone
                        slack_city slack_state slack_country slack_website slack_github slack_linkedin slack_start_date
                        slack_invited_at slack_joined_at slack_coc_accepted_at slack_membership].freeze
    ADDRESS_FIELDS = %w[address_type nickname contact_name contact_first_name contact_last_name contact_email
                        contact_phone_number line1 line2 line3 city state postal_code country].freeze

    def account_profile(user)
      {
        "profile"         => user.slice(*PROFILE_FIELDS).transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value },
        "email_addresses" => user.email_addresses.map { |address| { "email" => address.email, "primary" => address.is_primary, "confirmed_at" => address.confirmed_at&.iso8601 } },
        "addresses"       => user.addresses.map { |address| address.slice(*ADDRESS_FIELDS) },
        "sessions"        => user.user_sessions.order(:created_at).map do |session|
          { "created_at" => session.created_at.iso8601, "last_seen_at" => session.try(:last_seen_at)&.iso8601 }
        end,
        # The name and dates of each passkey. Never the public key or the
        # credential id.
        "passkeys"        => user.passkeys.order(:created_at).map do |passkey|
          { "nickname" => passkey.nickname, "created_at" => passkey.created_at.iso8601,
            "last_used_at" => passkey.last_used_at&.iso8601
}
        end,
        "social_profiles" => user.social_profiles.order(:provider).map do |profile|
          { "provider" => profile.provider, "id" => profile.uid, "username" => profile.username,
            "linked_at" => profile.created_at.iso8601
}
        end,
        "groups"          => user.groups.map(&:name),
        # The member's own requests. Not who decided: that is the approver's.
        "access_requests" => user.access_requests.includes(:application).order(:created_at).map do |request|
          { "app" => request.application.name, "reason" => request.reason, "status" => request.status,
            "requested_at" => request.created_at.iso8601, "decided_at" => request.decided_at&.iso8601
}
        end,
        "authorized_apps" => user.oauth_access_tokens.includes(:application).filter_map { |token| token.application&.name }.uniq,
        "funder_consents" => user.funder_consents.order(:given_at).map do |consent|
          { "funder" => consent.profile&.name || consent.funder, "given_at" => consent.given_at.iso8601,
            "withdrawn_at" => consent.withdrawn_at&.iso8601
}
        end
      }
    end

    def guardian_contact(user)
      user.guardian_consents.order(:created_at).map do |consent|
        { "guardian_name" => consent.guardian_name, "guardian_email" => consent.guardian_email, "status" => consent.status,
          "granted_at" => consent.granted_at&.iso8601, "revoked_at" => consent.revoked_at&.iso8601
}
      end
    end

    def verification_audit(user)
      user.verifications.order(:created_at).map do |verification|
        { "submitted_at" => verification.created_at.iso8601, "method" => verification.verification_method,
          "document_type" => verification.document_type, "status" => verification.status,
          "decided_at" => verification.decided_at&.iso8601, "resubmission_note" => verification.resubmission_note,
          "document_purged_at" => verification.document_purged_at&.iso8601
}
      end
    end

    def financial(user)
      user.grant_disbursements.order(:disbursed_on).map do |row|
        { "program" => row.program, "disbursed_on" => row.disbursed_on.iso8601, "amount_cents" => row.amount_cents,
          "currency" => row.currency, "payee_name" => row.payee_name, "payee_email" => row.payee_email,
          "reference" => row.reference
}
      end
    end

    def participations(user) = user.program_participations.order(:year, :program).to_a

    def participation(row)
      { "program" => row.program, "year" => row.year, "outcome" => row.outcome }
    end

  end
end
