# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_21_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "pg_catalog.plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "address_type", ["Venue", "Shipping", "Loading Dock", "Billing"]
  create_enum "status", ["active", "suspended", "deactivated"]

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "type", default: "Address", null: false
    t.string "nickname"
    t.string "contact_name"
    t.string "contact_first_name"
    t.string "contact_last_name"
    t.string "contact_email"
    t.string "contact_phone_number"
    t.enum "address_type", default: "Shipping", null: false, enum_type: "address_type"
    t.string "line1"
    t.string "line2"
    t.string "line3"
    t.string "city"
    t.string "state"
    t.string "country", limit: 2
    t.string "postal_code"
    t.float "latitude"
    t.float "longitude"
    t.boolean "residential", default: false, null: false
    t.boolean "supports_weekend_deliveries", default: false, null: false
    t.string "addressable_type", null: false
    t.bigint "addressable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "shipping_notes"
    t.index ["addressable_id"], name: "index_addresses_on_addressable_id"
    t.index ["addressable_type", "addressable_id", "type", "address_type"], name: "unique_address_per_addressable_type_and_address_type", unique: true
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable"
    t.index ["addressable_type"], name: "index_addresses_on_addressable_type"
    t.index ["type"], name: "index_addresses_on_type"
  end

  create_table "ahoy_clicks", force: :cascade do |t|
    t.string "campaign"
    t.string "token"
    t.index ["campaign"], name: "index_ahoy_clicks_on_campaign"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.bigint "visit_id"
    t.bigint "user_id"
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_messages", force: :cascade do |t|
    t.string "user_type"
    t.bigint "user_id"
    t.text "to_ciphertext"
    t.string "to_bidx"
    t.string "mailer"
    t.text "subject"
    t.datetime "sent_at"
    t.string "campaign"
    t.index ["campaign"], name: "index_ahoy_messages_on_campaign"
    t.index ["to_bidx"], name: "index_ahoy_messages_on_to_bidx"
    t.index ["user_type", "user_id"], name: "index_ahoy_messages_on_user"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.bigint "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "application_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.string "grantee_type", null: false
    t.bigint "grantee_id", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id", "grantee_type", "grantee_id"], name: "index_application_access_grants_uniqueness", unique: true
    t.index ["created_by_id"], name: "index_application_access_grants_on_created_by_id"
    t.index ["grantee_type", "grantee_id"], name: "index_application_access_grants_on_grantee"
  end

  create_table "application_role_assignments", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.string "assignee_type", null: false
    t.bigint "assignee_id", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_type", "assignee_id"], name: "index_application_role_assignments_on_assignee"
    t.index ["created_by_id"], name: "index_application_role_assignments_on_created_by_id"
    t.index ["role_id", "assignee_type", "assignee_id"], name: "index_application_role_assignments_uniqueness", unique: true
  end

  create_table "application_roles", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id", "key"], name: "index_application_roles_on_application_id_and_key", unique: true
    t.index ["created_by_id"], name: "index_application_roles_on_created_by_id"
  end

  create_table "audits1984_audits", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.text "notes"
    t.bigint "session_id", null: false
    t.bigint "auditor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auditor_id"], name: "index_audits1984_audits_on_auditor_id"
    t.index ["session_id"], name: "index_audits1984_audits_on_session_id"
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "query_id"
    t.text "statement"
    t.string "data_source"
    t.datetime "created_at"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.bigint "creator_id"
    t.bigint "query_id"
    t.string "state"
    t.string "schedule"
    t.text "emails"
    t.text "slack_channels"
    t.string "check_type"
    t.text "message"
    t.datetime "last_run_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.bigint "dashboard_id"
    t.bigint "query_id"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.bigint "creator_id"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.bigint "creator_id"
    t.string "name"
    t.text "description"
    t.text "statement"
    t.string "data_source"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "blazer_uploads", force: :cascade do |t|
    t.bigint "creator_id"
    t.string "table"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_uploads_on_creator_id"
  end

  create_table "break_glass_approvals", force: :cascade do |t|
    t.bigint "break_glass_record_id", null: false
    t.bigint "approver_id"
    t.datetime "created_at", null: false
    t.bigint "hardware_key_id"
    t.datetime "lapsed_at"
    t.index ["approver_id"], name: "index_break_glass_approvals_on_approver_id"
    t.index ["break_glass_record_id", "approver_id"], name: "index_break_glass_approvals_on_record_and_approver", unique: true, where: "(lapsed_at IS NULL)"
    t.index ["break_glass_record_id"], name: "index_break_glass_approvals_on_break_glass_record_id"
    t.index ["hardware_key_id"], name: "index_break_glass_approvals_on_hardware_key_id"
  end

  create_table "break_glass_decryptions", force: :cascade do |t|
    t.bigint "break_glass_record_id", null: false
    t.bigint "viewer_id"
    t.string "ip"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.index ["break_glass_record_id"], name: "index_break_glass_decryptions_on_break_glass_record_id"
    t.index ["viewer_id"], name: "index_break_glass_decryptions_on_viewer_id"
  end

  create_table "break_glass_notices", force: :cascade do |t|
    t.bigint "break_glass_decryption_id", null: false
    t.bigint "recipient_id"
    t.string "recipient_kind", null: false
    t.datetime "due_at", null: false
    t.datetime "sent_at"
    t.datetime "delayed_at"
    t.bigint "delayed_by_id"
    t.text "delay_reason"
    t.datetime "delay_lifted_at"
    t.bigint "delay_lifted_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "delay_signed_off_at"
    t.bigint "delay_signed_off_by_id"
    t.index ["break_glass_decryption_id"], name: "index_break_glass_notices_on_break_glass_decryption_id"
    t.index ["delay_lifted_by_id"], name: "index_break_glass_notices_on_delay_lifted_by_id"
    t.index ["delay_signed_off_by_id"], name: "index_break_glass_notices_on_delay_signed_off_by_id"
    t.index ["delayed_by_id"], name: "index_break_glass_notices_on_delayed_by_id"
    t.index ["recipient_id"], name: "index_break_glass_notices_on_recipient_id"
    t.index ["sent_at", "due_at"], name: "index_break_glass_notices_on_sent_at_and_due_at"
  end

  create_table "break_glass_records", force: :cascade do |t|
    t.bigint "verification_id", null: false
    t.bigint "user_id"
    t.bigint "requested_by_id"
    t.text "reason", null: false
    t.datetime "granted_at"
    t.datetime "expires_at"
    t.datetime "denied_at"
    t.bigint "denied_by_id"
    t.text "denial_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "key_set_id"
    t.text "requester_public_key"
    t.text "handoff_sealed_key"
    t.datetime "handoff_expires_at"
    t.datetime "opened_at"
    t.index ["denied_by_id"], name: "index_break_glass_records_on_denied_by_id"
    t.index ["key_set_id"], name: "index_break_glass_records_on_key_set_id"
    t.index ["requested_by_id"], name: "index_break_glass_records_on_requested_by_id"
    t.index ["user_id"], name: "index_break_glass_records_on_user_id"
    t.index ["verification_id"], name: "index_break_glass_records_on_verification_id"
  end

  create_table "console1984_commands", force: :cascade do |t|
    t.text "statements"
    t.bigint "sensitive_access_id"
    t.bigint "session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sensitive_access_id"], name: "index_console1984_commands_on_sensitive_access_id"
    t.index ["session_id", "created_at", "sensitive_access_id"], name: "on_session_and_sensitive_chronologically"
  end

  create_table "console1984_sensitive_accesses", force: :cascade do |t|
    t.text "justification"
    t.bigint "session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_console1984_sensitive_accesses_on_session_id"
  end

  create_table "console1984_sessions", force: :cascade do |t|
    t.text "reason"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_console1984_sessions_on_created_at"
    t.index ["user_id", "created_at"], name: "index_console1984_sessions_on_user_id_and_created_at"
  end

  create_table "console1984_users", force: :cascade do |t|
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_console1984_users_on_username"
  end

  create_table "console_access_requests", force: :cascade do |t|
    t.string "kind", null: false
    t.string "code_digest", null: false
    t.string "host"
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.bigint "user_id"
    t.datetime "confirmed_at"
    t.string "confirmed_ip"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_console_access_requests_on_code_digest", unique: true
    t.index ["user_id"], name: "index_console_access_requests_on_user_id"
  end

  create_table "delete_time_aggregates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "program", null: false
    t.integer "year", null: false
    t.string "outcome", null: false
    t.string "age_band", null: false
    t.string "region", null: false
    t.string "amount_band", null: false
    t.integer "count", default: 0, null: false
    t.index ["program", "year", "outcome", "age_band", "region", "amount_band"], name: "index_delete_time_aggregates_on_bands", unique: true
  end

  create_table "deletion_requests", force: :cascade do |t|
    t.bigint "user_id"
    t.string "source", default: "member", null: false
    t.string "status", default: "pending_review", null: false
    t.datetime "requested_at", null: false
    t.datetime "review_due_at", null: false
    t.datetime "complete_by", null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "review_note"
    t.text "receipt_email_ciphertext"
    t.jsonb "receipt", default: {}, null: false
    t.datetime "receipt_sent_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reviewed_by_id"], name: "index_deletion_requests_on_reviewed_by_id"
    t.index ["status"], name: "index_deletion_requests_on_status"
    t.index ["user_id"], name: "index_deletion_requests_on_user_id"
  end

  create_table "deletion_runs", force: :cascade do |t|
    t.bigint "deletion_request_id", null: false
    t.string "outcome", default: "running", null: false
    t.jsonb "steps", default: [], null: false
    t.string "error_class"
    t.text "error_message"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.index ["deletion_request_id"], name: "index_deletion_runs_on_deletion_request_id"
  end

  create_table "demographic_departed_totals", force: :cascade do |t|
    t.text "envelope", null: false
    t.string "key_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "demographic_folds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "envelope", null: false
    t.string "key_id", null: false
    t.jsonb "cohorts", default: [], null: false
  end

  create_table "demographic_records", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "envelope", null: false
    t.string "key_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_demographic_records_on_user_id", unique: true
  end

  create_table "demographic_reports", force: :cascade do |t|
    t.datetime "generated_at", null: false
    t.integer "threshold", null: false
    t.jsonb "results", default: {}, null: false
    t.integer "unreadable_count", default: 0, null: false
    t.integer "folds_counted", default: 0, null: false
    t.string "run_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["generated_at"], name: "index_demographic_reports_on_generated_at"
  end

  create_table "dormancy_warnings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "days_before", null: false
    t.datetime "last_active_at", null: false
    t.datetime "sent_at", null: false
    t.index ["user_id", "days_before", "last_active_at"], name: "index_dormancy_warnings_unique", unique: true
    t.index ["user_id"], name: "index_dormancy_warnings_on_user_id"
  end

  create_table "email_addresses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "email", null: false
    t.boolean "is_primary", default: false, null: false
    t.datetime "confirmed_at"
    t.string "confirmation_token"
    t.datetime "confirmation_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_email_addresses_on_confirmation_token", unique: true
    t.index ["email"], name: "index_email_addresses_on_email", unique: true
    t.index ["user_id"], name: "index_email_addresses_on_user_id"
    t.index ["user_id"], name: "index_email_addresses_one_primary_per_user", unique: true, where: "is_primary"
  end

  create_table "flipper_features", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.string "feature_key", null: false
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "funder_consents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "funder", null: false
    t.datetime "given_at", null: false
    t.datetime "withdrawn_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["funder"], name: "index_funder_consents_on_funder"
    t.index ["user_id", "funder"], name: "index_funder_consents_on_user_and_funder_live", unique: true, where: "(withdrawn_at IS NULL)"
    t.index ["user_id"], name: "index_funder_consents_on_user_id"
  end

  create_table "grant_disbursements", force: :cascade do |t|
    t.bigint "user_id"
    t.string "program", null: false
    t.string "funder"
    t.date "disbursed_on", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "USD", null: false
    t.text "payee_name_ciphertext"
    t.text "payee_email_ciphertext"
    t.text "reference_ciphertext"
    t.datetime "detached_at"
    t.datetime "anonymized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["disbursed_on"], name: "index_grant_disbursements_on_disbursed_on"
    t.index ["user_id"], name: "index_grant_disbursements_on_user_id"
  end

  create_table "group_memberships", force: :cascade do |t|
    t.bigint "group_id", null: false
    t.bigint "user_id", null: false
    t.bigint "added_by_id"
    t.string "source", default: "manual", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["added_by_id"], name: "index_group_memberships_on_added_by_id"
    t.index ["expires_at"], name: "index_group_memberships_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["group_id", "user_id"], name: "index_group_memberships_on_group_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_group_memberships_on_user_id"
  end

  create_table "groups", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.string "kind", default: "manual", null: false
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "waives_code_of_conduct", default: false, null: false
    t.boolean "waives_slack", default: false, null: false
    t.index ["created_by_id"], name: "index_groups_on_created_by_id"
    t.index ["deleted_at"], name: "index_groups_on_deleted_at"
    t.index ["name"], name: "index_groups_on_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["slug"], name: "index_groups_on_slug", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "guardian_consents", force: :cascade do |t|
    t.bigint "user_id"
    t.string "status", default: "pending", null: false
    t.text "guardian_name_ciphertext"
    t.text "guardian_email_ciphertext"
    t.text "signed_name_ciphertext"
    t.string "token_digest"
    t.datetime "sent_at"
    t.datetime "expires_at"
    t.datetime "granted_at"
    t.string "granted_ip"
    t.string "granted_user_agent"
    t.string "text_version"
    t.datetime "revoked_at"
    t.bigint "revoked_by_id"
    t.bigint "recorded_by_id"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "granted_fingerprint"
    t.jsonb "flags", default: [], null: false
    t.datetime "reviewed_at"
    t.text "review_note"
    t.bigint "reviewed_by_id"
    t.datetime "verified_at"
    t.text "verification_note"
    t.bigint "verified_by_id"
    t.datetime "account_deleted_at"
    t.index ["recorded_by_id"], name: "index_guardian_consents_on_recorded_by_id"
    t.index ["reviewed_by_id"], name: "index_guardian_consents_on_reviewed_by_id"
    t.index ["revoked_by_id"], name: "index_guardian_consents_on_revoked_by_id"
    t.index ["token_digest"], name: "index_guardian_consents_on_token_digest", unique: true
    t.index ["user_id"], name: "index_guardian_consents_on_user_id"
    t.index ["verified_by_id"], name: "index_guardian_consents_on_verified_by_id"
  end

  create_table "identity_governance_approvals", force: :cascade do |t|
    t.bigint "identity_governance_proposal_id", null: false
    t.bigint "approver_id"
    t.datetime "created_at", null: false
    t.index ["approver_id"], name: "index_identity_governance_approvals_on_approver_id"
    t.index ["identity_governance_proposal_id", "approver_id"], name: "index_identity_governance_approvals_on_proposal_and_approver", unique: true
    t.index ["identity_governance_proposal_id"], name: "index_identity_governance_approvals_on_proposal"
  end

  create_table "identity_governance_events", force: :cascade do |t|
    t.string "kind", null: false
    t.bigint "actor_id"
    t.bigint "subject_id"
    t.bigint "identity_governance_proposal_id"
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_identity_governance_events_on_actor_id"
    t.index ["created_at"], name: "index_identity_governance_events_on_created_at"
    t.index ["identity_governance_proposal_id"], name: "index_identity_governance_events_on_proposal"
    t.index ["subject_id"], name: "index_identity_governance_events_on_subject_id"
  end

  create_table "identity_governance_proposals", force: :cascade do |t|
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.bigint "subject_id"
    t.bigint "proposed_by_id"
    t.text "reason", null: false
    t.bigint "required_approver_ids", default: [], null: false, array: true
    t.datetime "expires_at", null: false
    t.datetime "closed_at"
    t.bigint "closed_by_id"
    t.text "close_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["closed_by_id"], name: "index_identity_governance_proposals_on_closed_by_id"
    t.index ["proposed_by_id"], name: "index_identity_governance_proposals_on_proposed_by_id"
    t.index ["status", "expires_at"], name: "index_identity_governance_proposals_on_status_and_expires_at"
    t.index ["subject_id"], name: "index_identity_governance_proposals_on_subject_id"
  end

  create_table "identity_hardware_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "external_id", null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "role", null: false
    t.string "nickname"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.bigint "revoked_by_id"
    t.text "revoked_reason"
    t.string "seal_salt", null: false
    t.string "seal_public_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_identity_hardware_keys_on_external_id", unique: true
    t.index ["revoked_by_id"], name: "index_identity_hardware_keys_on_revoked_by_id"
    t.index ["user_id"], name: "index_identity_hardware_keys_on_user_id"
  end

  create_table "identity_ndas", force: :cascade do |t|
    t.bigint "user_id"
    t.date "signed_on", null: false
    t.string "nda_version", null: false
    t.string "signature_reference", null: false
    t.bigint "recorded_by_id"
    t.datetime "created_at", null: false
    t.index ["recorded_by_id"], name: "index_identity_ndas_on_recorded_by_id"
    t.index ["user_id"], name: "index_identity_ndas_on_user_id"
  end

  create_table "impersonation_actions", force: :cascade do |t|
    t.bigint "impersonation_id", null: false
    t.string "http_method", null: false
    t.string "path", null: false
    t.string "controller_action"
    t.integer "status"
    t.jsonb "params", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["impersonation_id"], name: "index_impersonation_actions_on_impersonation_id"
  end

  create_table "impersonations", force: :cascade do |t|
    t.bigint "admin_id"
    t.bigint "user_id"
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.string "end_reason"
    t.boolean "denied", default: false, null: false
    t.string "ip"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_impersonations_on_admin_id"
    t.index ["user_id"], name: "index_impersonations_on_user_id"
  end

  create_table "key_custody_challenges", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "purpose", null: false
    t.string "subject", null: false
    t.string "challenge", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.index ["challenge"], name: "index_key_custody_challenges_on_challenge", unique: true
    t.index ["user_id"], name: "index_key_custody_challenges_on_user_id"
  end

  create_table "key_custody_events", force: :cascade do |t|
    t.string "kind", null: false
    t.bigint "actor_id"
    t.bigint "subject_id"
    t.bigint "key_set_id"
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_key_custody_events_on_actor_id"
    t.index ["created_at"], name: "index_key_custody_events_on_created_at"
    t.index ["key_set_id"], name: "index_key_custody_events_on_key_set_id"
    t.index ["subject_id"], name: "index_key_custody_events_on_subject_id"
  end

  create_table "key_custody_key_sets", force: :cascade do |t|
    t.text "public_key", null: false
    t.integer "threshold", null: false
    t.integer "share_count", null: false
    t.string "status", default: "pending", null: false
    t.bigint "created_by_id"
    t.bigint "rotated_from_id"
    t.datetime "activated_at"
    t.datetime "compromised_at"
    t.string "compromised_reason"
    t.datetime "retired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_key_custody_key_sets_on_created_by_id"
    t.index ["public_key"], name: "index_key_custody_key_sets_on_public_key", unique: true
    t.index ["rotated_from_id"], name: "index_key_custody_key_sets_on_rotated_from_id"
    t.index ["status"], name: "index_key_custody_key_sets_on_status"
  end

  create_table "key_custody_pending_shares", force: :cascade do |t|
    t.string "memory_key", null: false
    t.bigint "holder_id", null: false
    t.text "share_ciphertext", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["expires_at"], name: "index_key_custody_pending_shares_on_expires_at"
    t.index ["holder_id"], name: "index_key_custody_pending_shares_on_holder_id"
    t.index ["memory_key", "holder_id"], name: "index_key_custody_pending_shares_on_memory_key_and_holder_id", unique: true
  end

  create_table "key_custody_shares", force: :cascade do |t|
    t.bigint "key_set_id", null: false
    t.bigint "holder_id"
    t.integer "x", null: false
    t.string "digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["holder_id"], name: "index_key_custody_shares_on_holder_id"
    t.index ["key_set_id", "holder_id"], name: "index_key_custody_shares_on_key_set_id_and_holder_id", unique: true
    t.index ["key_set_id", "x"], name: "index_key_custody_shares_on_key_set_id_and_x", unique: true
    t.index ["key_set_id"], name: "index_key_custody_shares_on_key_set_id"
  end

  create_table "key_custody_wrapped_shares", force: :cascade do |t|
    t.bigint "share_id", null: false
    t.bigint "hardware_key_id", null: false
    t.text "sealed", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hardware_key_id"], name: "index_key_custody_wrapped_shares_on_hardware_key_id"
    t.index ["share_id", "hardware_key_id"], name: "idx_on_share_id_hardware_key_id_f328b38774", unique: true
    t.index ["share_id"], name: "index_key_custody_wrapped_shares_on_share_id"
  end

  create_table "knot_change_requests", force: :cascade do |t|
    t.bigint "knot_id", null: false
    t.bigint "verification_id", null: false
    t.bigint "requested_by_id"
    t.string "kind", null: false
    t.string "program"
    t.jsonb "digests", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["knot_id"], name: "index_knot_change_requests_on_knot_id"
    t.index ["requested_by_id"], name: "index_knot_change_requests_on_requested_by_id"
    t.index ["verification_id"], name: "index_knot_change_requests_on_verification_id"
  end

  create_table "knot_hashes", force: :cascade do |t|
    t.bigint "knot_id", null: false
    t.string "kind", null: false
    t.string "digest", null: false
    t.index ["kind", "digest"], name: "index_knot_hashes_on_kind_and_digest"
    t.index ["kind", "digest"], name: "index_knot_hashes_on_strong_digest", unique: true, where: "((kind)::text <> 'soft'::text)"
    t.index ["knot_id", "kind", "digest"], name: "index_knot_hashes_on_knot_id_and_kind_and_digest", unique: true
  end

  create_table "knots", force: :cascade do |t|
    t.bigint "user_id"
    t.boolean "blacklisted", default: false, null: false
    t.index ["user_id"], name: "index_knots_on_user_id", unique: true
  end

  create_table "lockbox_audits", force: :cascade do |t|
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "viewer_type"
    t.bigint "viewer_id"
    t.jsonb "data"
    t.string "context"
    t.string "ip"
    t.datetime "created_at"
    t.index ["subject_type", "subject_id"], name: "index_lockbox_audits_on_subject"
    t.index ["viewer_type", "viewer_id"], name: "index_lockbox_audits_on_viewer"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "resource_owner_id"
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.string "scopes"
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "previous_refresh_token", default: "", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "access_policy", default: "everyone", null: false
    t.boolean "requires_code_of_conduct", default: true, null: false
    t.boolean "requires_guardian_consent", default: true, null: false
    t.string "email_domains", default: [], null: false, array: true
    t.boolean "requires_verification", default: false, null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "oauth_openid_requests", force: :cascade do |t|
    t.bigint "access_grant_id", null: false
    t.string "nonce", null: false
    t.index ["access_grant_id"], name: "index_oauth_openid_requests_on_access_grant_id"
  end

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.string "searchable_type"
    t.bigint "searchable_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
  end

  create_table "privileged_attribute_changes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "user_p_id"
    t.string "attribute_name", null: false
    t.text "old_value"
    t.text "new_value"
    t.string "operation", null: false
    t.datetime "changed_at", default: -> { "now()" }, null: false
    t.string "db_user", null: false
    t.bigint "actor_id"
    t.string "actor_label"
    t.index ["changed_at"], name: "index_privileged_attribute_changes_on_changed_at"
    t.index ["user_id"], name: "index_privileged_attribute_changes_on_user_id"
  end

  create_table "program_grants", force: :cascade do |t|
    t.bigint "knot_id", null: false
    t.string "program", null: false
    t.datetime "granted_at", null: false
    t.index ["knot_id", "program"], name: "index_program_grants_on_knot_id_and_program"
    t.index ["knot_id"], name: "index_program_grants_on_knot_id"
  end

  create_table "program_participations", force: :cascade do |t|
    t.bigint "user_id"
    t.string "program", null: false
    t.integer "year", null: false
    t.string "outcome", null: false
    t.string "funder"
    t.string "age_band"
    t.string "region"
    t.string "amount_band"
    t.datetime "detached_at"
    t.datetime "retained_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["retained_until"], name: "index_program_participations_on_retained_until"
    t.index ["user_id", "program", "year"], name: "index_program_participations_on_user_id_and_program_and_year", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["user_id"], name: "index_program_participations_on_user_id"
  end

  create_table "rollups", force: :cascade do |t|
    t.string "name", null: false
    t.string "interval", null: false
    t.datetime "time", null: false
    t.jsonb "dimensions", default: {}, null: false
    t.float "value"
    t.index ["name", "interval", "time", "dimensions"], name: "index_rollups_on_name_and_interval_and_time_and_dimensions", unique: true
  end

  create_table "sealed_id_documents", force: :cascade do |t|
    t.bigint "verification_id", null: false
    t.bigint "key_set_id", null: false
    t.text "sealed_data_key", null: false
    t.string "content_type", null: false
    t.string "extension"
    t.datetime "sealed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_set_id"], name: "index_sealed_id_documents_on_key_set_id"
    t.index ["verification_id"], name: "index_sealed_id_documents_on_verification_id", unique: true
  end

  create_table "service_key_usages", force: :cascade do |t|
    t.bigint "service_key_id", null: false
    t.string "request_path"
    t.string "request_method"
    t.integer "response_code"
    t.integer "duration_ms"
    t.string "ip_address"
    t.string "user_agent"
    t.text "request_headers"
    t.text "request_body"
    t.text "response_headers"
    t.text "response_body"
    t.integer "user_id"
    t.datetime "requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requested_at"], name: "index_service_key_usages_on_requested_at"
    t.index ["response_code"], name: "index_service_key_usages_on_response_code"
    t.index ["service_key_id", "requested_at"], name: "index_service_key_usages_on_service_key_id_and_requested_at"
    t.index ["service_key_id"], name: "index_service_key_usages_on_service_key_id"
  end

  create_table "service_keys", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.string "name", null: false
    t.string "api_key_digest", null: false
    t.string "hash_key", null: false
    t.string "status", default: "active", null: false
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_digest"], name: "index_service_keys_on_api_key_digest", unique: true
    t.index ["created_by_id"], name: "index_service_keys_on_created_by_id"
    t.index ["service_id", "status"], name: "index_service_keys_on_service_id_and_status"
    t.index ["service_id"], name: "index_service_keys_on_service_id"
    t.index ["status"], name: "index_service_keys_on_status"
  end

  create_table "service_webhooks", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.string "url", null: false
    t.string "event_type", null: false
    t.string "secret_token"
    t.string "status", default: "active", null: false
    t.datetime "last_triggered_at"
    t.integer "failure_count", default: 0
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_service_webhooks_on_created_by_id"
    t.index ["service_id", "event_type"], name: "index_service_webhooks_on_service_id_and_event_type"
    t.index ["service_id"], name: "index_service_webhooks_on_service_id"
    t.index ["status"], name: "index_service_webhooks_on_status"
  end

  create_table "services", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "active", null: false
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_services_on_created_by_id"
    t.index ["name"], name: "index_services_on_name", unique: true
    t.index ["status"], name: "index_services_on_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.string "session_id", null: false
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "takeout_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "ready_at"
    t.datetime "expires_at"
    t.datetime "downloaded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_takeout_requests_on_user_id"
  end

  create_table "thread_count_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "level"
    t.bigint "author_id"
    t.bigint "recorded_by_id"
    t.bigint "service_id"
    t.text "reason_ciphertext"
    t.text "evidence_url_ciphertext"
    t.string "evidence_type"
    t.bigint "evidence_id"
    t.string "project_ref"
    t.bigint "reverses_id"
    t.datetime "created_at", null: false
    t.index ["author_id"], name: "index_thread_count_entries_on_author_id"
    t.index ["evidence_type", "evidence_id"], name: "index_thread_count_entries_on_evidence"
    t.index ["recorded_by_id"], name: "index_thread_count_entries_on_recorded_by_id"
    t.index ["reverses_id"], name: "index_thread_count_entries_on_reverses_id", unique: true
    t.index ["service_id", "project_ref", "kind"], name: "index_thread_count_entries_on_project_event", unique: true, where: "(project_ref IS NOT NULL)"
    t.index ["service_id"], name: "index_thread_count_entries_on_service_id"
    t.index ["user_id", "kind"], name: "index_thread_count_entries_on_user_id_and_kind"
    t.index ["user_id"], name: "index_thread_count_entries_on_user_id"
  end

  create_table "user_magic_links", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.string "requested_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "delivered_to"
    t.index ["expires_at"], name: "index_user_magic_links_on_expires_at"
    t.index ["token_digest"], name: "index_user_magic_links_on_token_digest", unique: true
    t.index ["user_id"], name: "index_user_magic_links_on_user_id"
  end

  create_table "user_passkeys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "external_id", null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "nickname"
    t.datetime "last_used_at"
    t.datetime "compromised_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_user_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_user_passkeys_on_user_id"
  end

  create_table "user_seen_at_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "impersonated_by_id"
    t.string "session_token_ciphertext"
    t.string "session_token_bidx"
    t.string "fingerprint"
    t.string "device_info"
    t.string "string"
    t.string "os_info"
    t.string "timezone"
    t.string "ip"
    t.datetime "expiration_at", null: false
    t.datetime "last_seen_at"
    t.datetime "signed_out_at"
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["impersonated_by_id"], name: "index_user_sessions_on_impersonated_by_id"
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "p_id", null: false
    t.integer "role", default: 0, null: false
    t.string "email", null: false
    t.datetime "acknowledged_over_13_at"
    t.datetime "slack_joined_at"
    t.string "slack_id"
    t.string "password_digest", null: false
    t.integer "session_duration_seconds", default: 2592000, null: false
    t.enum "status", default: "active", null: false, enum_type: "status"
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "birthday"
    t.string "phone_number"
    t.datetime "email_confirmed_at"
    t.string "confirmation_token"
    t.datetime "confirmation_sent_at"
    t.string "slack_pronouns"
    t.string "slack_display_name"
    t.string "slack_status_text"
    t.string "slack_status_emoji"
    t.string "slack_phone"
    t.date "slack_start_date"
    t.text "slack_role_description"
    t.string "slack_website"
    t.string "slack_github"
    t.string "slack_linkedin"
    t.date "slack_birthday"
    t.string "slack_profile_image_url"
    t.string "slack_title"
    t.string "slack_city"
    t.string "slack_state"
    t.string "slack_country"
    t.string "slack_manager_id"
    t.string "slack_organization"
    t.string "slack_division"
    t.string "slack_department"
    t.string "slack_cost_center"
    t.datetime "slack_profile_synced_at"
    t.boolean "is_staff", default: false, null: false
    t.boolean "is_contractor", default: false, null: false
    t.bigint "manager_id"
    t.boolean "is_board", default: false, null: false
    t.datetime "slack_invited_at"
    t.datetime "slack_coc_accepted_at"
    t.string "pronouns"
    t.string "legal_first_name"
    t.string "legal_last_name"
    t.string "slack_membership", default: "pending", null: false
    t.datetime "slack_coc_requested_at"
    t.boolean "code_of_conduct_exempt", default: false, null: false
    t.jsonb "slack_coc_messages", default: [], null: false
    t.string "webauthn_id"
    t.datetime "directory_linked_at"
    t.string "directory_object_guid"
    t.string "referral_source"
    t.string "referral_source_detail"
    t.boolean "identity_team", default: false, null: false
    t.boolean "identity_key_holder", default: false, null: false
    t.boolean "identity_lead", default: false, null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["manager_id"], name: "index_users_on_manager_id"
    t.index ["p_id"], name: "index_users_on_p_id", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "verification_events", force: :cascade do |t|
    t.bigint "verification_id", null: false
    t.bigint "user_id"
    t.bigint "actor_id"
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_verification_events_on_actor_id"
    t.index ["kind"], name: "index_verification_events_on_kind"
    t.index ["user_id"], name: "index_verification_events_on_user_id"
    t.index ["verification_id"], name: "index_verification_events_on_verification_id"
  end

  create_table "verifications", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "previous_attempt_id"
    t.string "verification_method", default: "document_call", null: false
    t.string "status", default: "submitted", null: false
    t.string "document_type"
    t.bigint "pre_reviewer_id"
    t.datetime "pre_review_started_at"
    t.datetime "pre_reviewed_at"
    t.text "resubmission_note"
    t.datetime "call_scheduled_for"
    t.bigint "call_scheduled_by_id"
    t.bigint "verifier_id"
    t.bigint "second_verifier_id"
    t.boolean "guardian_attended", default: false, null: false
    t.bigint "guardian_consent_id"
    t.boolean "age_consistent"
    t.boolean "region_consistent"
    t.text "decision_reason"
    t.datetime "decided_at"
    t.datetime "escalated_at"
    t.datetime "escalation_resolved_at"
    t.bigint "escalation_resolved_by_id"
    t.string "escalation_resolution"
    t.text "escalation_note"
    t.datetime "document_purged_at"
    t.datetime "reverification_required_at"
    t.string "reverification_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "knot_id"
    t.string "knot_review_reason"
    t.datetime "account_deleted_at"
    t.index ["account_deleted_at"], name: "index_verifications_on_account_deleted_at"
    t.index ["call_scheduled_by_id"], name: "index_verifications_on_call_scheduled_by_id"
    t.index ["escalation_resolved_by_id"], name: "index_verifications_on_escalation_resolved_by_id"
    t.index ["guardian_consent_id"], name: "index_verifications_on_guardian_consent_id"
    t.index ["knot_id"], name: "index_verifications_on_knot_id"
    t.index ["pre_reviewer_id"], name: "index_verifications_on_pre_reviewer_id"
    t.index ["previous_attempt_id"], name: "index_verifications_on_previous_attempt_id"
    t.index ["second_verifier_id"], name: "index_verifications_on_second_verifier_id"
    t.index ["status"], name: "index_verifications_on_status"
    t.index ["user_id"], name: "index_verifications_on_user_id"
    t.index ["verifier_id"], name: "index_verifications_on_verifier_id"
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.bigint "impersonation_id"
    t.index ["impersonation_id"], name: "index_versions_on_impersonation_id"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "application_access_grants", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "application_access_grants", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "application_role_assignments", "application_roles", column: "role_id", on_delete: :cascade
  add_foreign_key "application_role_assignments", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "application_roles", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "application_roles", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "break_glass_approvals", "break_glass_records"
  add_foreign_key "break_glass_approvals", "identity_hardware_keys", column: "hardware_key_id", on_delete: :nullify
  add_foreign_key "break_glass_approvals", "users", column: "approver_id", on_delete: :nullify
  add_foreign_key "break_glass_decryptions", "break_glass_records"
  add_foreign_key "break_glass_decryptions", "users", column: "viewer_id", on_delete: :nullify
  add_foreign_key "break_glass_notices", "break_glass_decryptions"
  add_foreign_key "break_glass_notices", "users", column: "delay_lifted_by_id", on_delete: :nullify
  add_foreign_key "break_glass_notices", "users", column: "delay_signed_off_by_id", on_delete: :nullify
  add_foreign_key "break_glass_notices", "users", column: "delayed_by_id", on_delete: :nullify
  add_foreign_key "break_glass_notices", "users", column: "recipient_id", on_delete: :nullify
  add_foreign_key "break_glass_records", "key_custody_key_sets", column: "key_set_id"
  add_foreign_key "break_glass_records", "users", column: "denied_by_id", on_delete: :nullify
  add_foreign_key "break_glass_records", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "break_glass_records", "users", on_delete: :nullify
  add_foreign_key "break_glass_records", "verifications"
  add_foreign_key "console_access_requests", "users", on_delete: :nullify
  add_foreign_key "deletion_requests", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "deletion_requests", "users", on_delete: :nullify
  add_foreign_key "deletion_runs", "deletion_requests", on_delete: :cascade
  add_foreign_key "demographic_records", "users", on_delete: :cascade
  add_foreign_key "dormancy_warnings", "users", on_delete: :cascade
  add_foreign_key "email_addresses", "users"
  add_foreign_key "funder_consents", "users", on_delete: :cascade
  add_foreign_key "grant_disbursements", "users", on_delete: :nullify
  add_foreign_key "group_memberships", "groups"
  add_foreign_key "group_memberships", "users"
  add_foreign_key "group_memberships", "users", column: "added_by_id", on_delete: :nullify
  add_foreign_key "groups", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "guardian_consents", "users", column: "recorded_by_id", on_delete: :nullify
  add_foreign_key "guardian_consents", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "guardian_consents", "users", column: "revoked_by_id", on_delete: :nullify
  add_foreign_key "guardian_consents", "users", column: "verified_by_id", on_delete: :nullify
  add_foreign_key "guardian_consents", "users", on_delete: :nullify
  add_foreign_key "identity_governance_approvals", "identity_governance_proposals"
  add_foreign_key "identity_governance_approvals", "users", column: "approver_id", on_delete: :nullify
  add_foreign_key "identity_governance_events", "identity_governance_proposals", on_delete: :nullify
  add_foreign_key "identity_governance_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "identity_governance_events", "users", column: "subject_id", on_delete: :nullify
  add_foreign_key "identity_governance_proposals", "users", column: "closed_by_id", on_delete: :nullify
  add_foreign_key "identity_governance_proposals", "users", column: "proposed_by_id", on_delete: :nullify
  add_foreign_key "identity_governance_proposals", "users", column: "subject_id", on_delete: :nullify
  add_foreign_key "identity_hardware_keys", "users", column: "revoked_by_id", on_delete: :nullify
  add_foreign_key "identity_hardware_keys", "users", on_delete: :cascade
  add_foreign_key "identity_ndas", "users", column: "recorded_by_id", on_delete: :nullify
  add_foreign_key "identity_ndas", "users", on_delete: :nullify
  add_foreign_key "impersonation_actions", "impersonations", on_delete: :cascade
  add_foreign_key "impersonations", "users", column: "admin_id", on_delete: :nullify
  add_foreign_key "impersonations", "users", on_delete: :nullify
  add_foreign_key "key_custody_challenges", "users", on_delete: :cascade
  add_foreign_key "key_custody_events", "key_custody_key_sets", column: "key_set_id"
  add_foreign_key "key_custody_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "key_custody_events", "users", column: "subject_id", on_delete: :nullify
  add_foreign_key "key_custody_key_sets", "key_custody_key_sets", column: "rotated_from_id"
  add_foreign_key "key_custody_key_sets", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "key_custody_pending_shares", "users", column: "holder_id", on_delete: :cascade
  add_foreign_key "key_custody_shares", "key_custody_key_sets", column: "key_set_id"
  add_foreign_key "key_custody_shares", "users", column: "holder_id", on_delete: :nullify
  add_foreign_key "key_custody_wrapped_shares", "identity_hardware_keys", column: "hardware_key_id", on_delete: :cascade
  add_foreign_key "key_custody_wrapped_shares", "key_custody_shares", column: "share_id", on_delete: :cascade
  add_foreign_key "knot_change_requests", "knots"
  add_foreign_key "knot_change_requests", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "knot_change_requests", "verifications", on_delete: :cascade
  add_foreign_key "knot_hashes", "knots"
  add_foreign_key "knots", "users", on_delete: :nullify
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "oauth_openid_requests", "oauth_access_grants", column: "access_grant_id", on_delete: :cascade
  add_foreign_key "program_grants", "knots"
  add_foreign_key "program_participations", "users", on_delete: :nullify
  add_foreign_key "sealed_id_documents", "key_custody_key_sets", column: "key_set_id"
  add_foreign_key "sealed_id_documents", "verifications"
  add_foreign_key "service_key_usages", "service_keys"
  add_foreign_key "service_keys", "services"
  add_foreign_key "service_keys", "users", column: "created_by_id"
  add_foreign_key "service_webhooks", "services"
  add_foreign_key "service_webhooks", "users", column: "created_by_id"
  add_foreign_key "services", "users", column: "created_by_id"
  add_foreign_key "takeout_requests", "users", on_delete: :cascade
  add_foreign_key "thread_count_entries", "services", on_delete: :nullify
  add_foreign_key "thread_count_entries", "thread_count_entries", column: "reverses_id", on_delete: :cascade
  add_foreign_key "thread_count_entries", "users", column: "author_id", on_delete: :nullify
  add_foreign_key "thread_count_entries", "users", column: "recorded_by_id", on_delete: :nullify
  add_foreign_key "thread_count_entries", "users", on_delete: :cascade
  add_foreign_key "user_magic_links", "users"
  add_foreign_key "user_passkeys", "users"
  add_foreign_key "user_sessions", "users"
  add_foreign_key "user_sessions", "users", column: "impersonated_by_id"
  add_foreign_key "users", "users", column: "manager_id"
  add_foreign_key "verification_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "verification_events", "users", on_delete: :nullify
  add_foreign_key "verification_events", "verifications"
  add_foreign_key "verifications", "guardian_consents", on_delete: :nullify
  add_foreign_key "verifications", "knots", on_delete: :nullify
  add_foreign_key "verifications", "users", column: "call_scheduled_by_id", on_delete: :nullify
  add_foreign_key "verifications", "users", column: "escalation_resolved_by_id", on_delete: :nullify
  add_foreign_key "verifications", "users", column: "pre_reviewer_id", on_delete: :nullify
  add_foreign_key "verifications", "users", column: "second_verifier_id", on_delete: :nullify
  add_foreign_key "verifications", "users", column: "verifier_id", on_delete: :nullify
  add_foreign_key "verifications", "users", on_delete: :nullify
  add_foreign_key "verifications", "verifications", column: "previous_attempt_id", on_delete: :nullify

  create_function :log_privileged_attribute_changes, sql_definition: <<-'SQL'
      CREATE OR REPLACE FUNCTION public.log_privileged_attribute_changes()
       RETURNS trigger
       LANGUAGE plpgsql
       SET search_path TO 'pg_catalog'
      AS $function$
      DECLARE
        column_name text;
        old_text text;
        new_text text;
        actor_id_text text := nullif(current_setting('weave.actor_id', true), '');
        actor_label_text text := nullif(current_setting('weave.actor_label', true), '');
      BEGIN
        FOREACH column_name IN ARRAY ARRAY['is_board', 'identity_team', 'identity_key_holder', 'identity_lead', 'role'] LOOP
          new_text := to_jsonb(NEW) ->> column_name;
          IF TG_OP = 'INSERT' THEN
            old_text := NULL;
            CONTINUE WHEN new_text IS NULL OR new_text IN ('false', '0');
          ELSE
            old_text := to_jsonb(OLD) ->> column_name;
            CONTINUE WHEN old_text IS NOT DISTINCT FROM new_text;
          END IF;

          INSERT INTO public.privileged_attribute_changes
            (user_id, user_p_id, attribute_name, old_value, new_value, operation, changed_at, db_user, actor_id, actor_label)
          VALUES
            (NEW.id, NEW.p_id, column_name, old_text, new_text, lower(TG_OP), now(), CURRENT_USER,
             CASE WHEN actor_id_text ~ '^[0-9]+$' THEN actor_id_text::bigint END, actor_label_text);
        END LOOP;
        RETURN NULL;
      END;
      $function$
  SQL

  create_function :refuse_privileged_attribute_change_edits, sql_definition: <<-'SQL'
      CREATE OR REPLACE FUNCTION public.refuse_privileged_attribute_change_edits()
       RETURNS trigger
       LANGUAGE plpgsql
       SET search_path TO 'pg_catalog'
      AS $function$
      BEGIN
        RAISE EXCEPTION 'privileged_attribute_changes is append-only: % is not allowed', TG_OP;
      END;
      $function$
  SQL

  create_trigger :privileged_attribute_changes_no_truncate, sql_definition: <<-SQL
      CREATE TRIGGER privileged_attribute_changes_no_truncate BEFORE TRUNCATE ON public.privileged_attribute_changes FOR EACH STATEMENT EXECUTE FUNCTION refuse_privileged_attribute_change_edits()
  SQL

  create_trigger :privileged_attribute_changes_append_only, sql_definition: <<-SQL
      CREATE TRIGGER privileged_attribute_changes_append_only BEFORE DELETE OR UPDATE ON public.privileged_attribute_changes FOR EACH ROW EXECUTE FUNCTION refuse_privileged_attribute_change_edits()
  SQL

  create_trigger :log_privileged_attribute_changes, sql_definition: <<-SQL
      CREATE TRIGGER log_privileged_attribute_changes AFTER INSERT OR UPDATE OF is_board, identity_team, identity_key_holder, identity_lead, role ON public.users FOR EACH ROW EXECUTE FUNCTION log_privileged_attribute_changes()
  SQL
end
