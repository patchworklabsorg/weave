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

ActiveRecord::Schema[8.1].define(version: 2026_07_22_003447) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "pg_catalog.plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "address_type", ["Venue", "Shipping", "Loading Dock", "Billing"]
  create_enum "status", ["active", "suspended", "deactivated"]

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.enum "address_type", default: "Shipping", null: false, enum_type: "address_type"
    t.bigint "addressable_id", null: false
    t.string "addressable_type", null: false
    t.string "city"
    t.string "contact_email"
    t.string "contact_first_name"
    t.string "contact_last_name"
    t.string "contact_name"
    t.string "contact_phone_number"
    t.string "country", limit: 2
    t.datetime "created_at", null: false
    t.float "latitude"
    t.string "line1"
    t.string "line2"
    t.string "line3"
    t.float "longitude"
    t.string "nickname"
    t.string "postal_code"
    t.boolean "residential", default: false, null: false
    t.text "shipping_notes"
    t.string "state"
    t.boolean "supports_weekend_deliveries", default: false, null: false
    t.string "type", default: "Address", null: false
    t.datetime "updated_at", null: false
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
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.bigint "user_id"
    t.bigint "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_messages", force: :cascade do |t|
    t.string "campaign"
    t.string "mailer"
    t.datetime "sent_at"
    t.text "subject"
    t.string "to_bidx"
    t.text "to_ciphertext"
    t.bigint "user_id"
    t.string "user_type"
    t.index ["campaign"], name: "index_ahoy_messages_on_campaign"
    t.index ["to_bidx"], name: "index_ahoy_messages_on_to_bidx"
    t.index ["user_type", "user_id"], name: "index_ahoy_messages_on_user"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.bigint "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "audits1984_audits", force: :cascade do |t|
    t.bigint "auditor_id", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "session_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["auditor_id"], name: "index_audits1984_audits_on_auditor_id"
    t.index ["session_id"], name: "index_audits1984_audits_on_session_id"
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.datetime "created_at"
    t.string "data_source"
    t.bigint "query_id"
    t.text "statement"
    t.bigint "user_id"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.string "check_type"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "emails"
    t.datetime "last_run_at"
    t.text "message"
    t.bigint "query_id"
    t.string "schedule"
    t.text "slack_channels"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dashboard_id"
    t.integer "position"
    t.bigint "query_id"
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "data_source"
    t.text "description"
    t.string "name"
    t.text "statement"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "blazer_uploads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "description"
    t.string "table"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_uploads_on_creator_id"
  end

  create_table "console1984_commands", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "sensitive_access_id"
    t.bigint "session_id", null: false
    t.text "statements"
    t.datetime "updated_at", null: false
    t.index ["sensitive_access_id"], name: "index_console1984_commands_on_sensitive_access_id"
    t.index ["session_id", "created_at", "sensitive_access_id"], name: "on_session_and_sensitive_chronologically"
  end

  create_table "console1984_sensitive_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "justification"
    t.bigint "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_console1984_sensitive_accesses_on_session_id"
  end

  create_table "console1984_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_console1984_sessions_on_created_at"
    t.index ["user_id", "created_at"], name: "index_console1984_sessions_on_user_id_and_created_at"
  end

  create_table "console1984_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_console1984_users_on_username"
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "lockbox_audits", force: :cascade do |t|
    t.string "context"
    t.datetime "created_at"
    t.jsonb "data"
    t.string "ip"
    t.bigint "subject_id"
    t.string "subject_type"
    t.bigint "viewer_id"
    t.string "viewer_type"
    t.index ["subject_type", "subject_id"], name: "index_lockbox_audits_on_subject"
    t.index ["viewer_type", "viewer_id"], name: "index_lockbox_audits_on_viewer"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "searchable_id"
    t.string "searchable_type"
    t.datetime "updated_at", null: false
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
  end

  create_table "rollups", force: :cascade do |t|
    t.jsonb "dimensions", default: {}, null: false
    t.string "interval", null: false
    t.string "name", null: false
    t.datetime "time", null: false
    t.float "value"
    t.index ["name", "interval", "time", "dimensions"], name: "index_rollups_on_name_and_interval_and_time_and_dimensions", unique: true
  end

  create_table "service_key_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "ip_address"
    t.text "request_body"
    t.text "request_headers"
    t.string "request_method"
    t.string "request_path"
    t.datetime "requested_at"
    t.text "response_body"
    t.integer "response_code"
    t.text "response_headers"
    t.bigint "service_key_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id"
    t.index ["requested_at"], name: "index_service_key_usages_on_requested_at"
    t.index ["response_code"], name: "index_service_key_usages_on_response_code"
    t.index ["service_key_id", "requested_at"], name: "index_service_key_usages_on_service_key_id_and_requested_at"
    t.index ["service_key_id"], name: "index_service_key_usages_on_service_key_id"
  end

  create_table "service_keys", force: :cascade do |t|
    t.string "api_key_digest", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "expires_at"
    t.string "hash_key", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "service_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_digest"], name: "index_service_keys_on_api_key_digest", unique: true
    t.index ["created_by_id"], name: "index_service_keys_on_created_by_id"
    t.index ["service_id", "status"], name: "index_service_keys_on_service_id_and_status"
    t.index ["service_id"], name: "index_service_keys_on_service_id"
    t.index ["status"], name: "index_service_keys_on_status"
  end

  create_table "service_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.string "event_type", null: false
    t.integer "failure_count", default: 0
    t.datetime "last_triggered_at"
    t.string "secret_token"
    t.bigint "service_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["created_by_id"], name: "index_service_webhooks_on_created_by_id"
    t.index ["service_id", "event_type"], name: "index_service_webhooks_on_service_id_and_event_type"
    t.index ["service_id"], name: "index_service_webhooks_on_service_id"
    t.index ["status"], name: "index_service_webhooks_on_status"
  end

  create_table "services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.text "description"
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_services_on_created_by_id"
    t.index ["name"], name: "index_services_on_name", unique: true
    t.index ["status"], name: "index_services_on_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data"
    t.string "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "user_seen_at_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_info"
    t.datetime "expiration_at", null: false
    t.string "fingerprint"
    t.bigint "impersonated_by_id"
    t.string "ip"
    t.datetime "last_seen_at"
    t.float "latitude"
    t.float "longitude"
    t.string "os_info"
    t.string "session_token_bidx"
    t.string "session_token_ciphertext"
    t.datetime "signed_out_at"
    t.string "string"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["impersonated_by_id"], name: "index_user_sessions_on_impersonated_by_id"
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "acknowledged_over_13_at"
    t.date "birthday"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "email_confirmed_at"
    t.string "first_name", null: false
    t.boolean "is_board", default: false, null: false
    t.boolean "is_contractor", default: false, null: false
    t.boolean "is_staff", default: false, null: false
    t.string "last_name", null: false
    t.datetime "locked_at"
    t.datetime "magic_link_expires_at"
    t.datetime "magic_link_sent_at"
    t.string "magic_link_token"
    t.datetime "magic_link_used_at"
    t.bigint "manager_id"
    t.string "p_id", null: false
    t.string "password_digest", null: false
    t.string "phone_number"
    t.integer "role", default: 0, null: false
    t.integer "session_duration_seconds", default: 2592000, null: false
    t.date "slack_birthday"
    t.string "slack_city"
    t.datetime "slack_coc_accepted_at"
    t.string "slack_cost_center"
    t.string "slack_country"
    t.string "slack_department"
    t.string "slack_display_name"
    t.string "slack_division"
    t.string "slack_github"
    t.string "slack_id"
    t.datetime "slack_invited_at"
    t.datetime "slack_joined_at"
    t.string "slack_linkedin"
    t.string "slack_manager_id"
    t.string "slack_organization"
    t.string "slack_phone"
    t.string "slack_profile_image_url"
    t.datetime "slack_profile_synced_at"
    t.string "slack_pronouns"
    t.text "slack_role_description"
    t.date "slack_start_date"
    t.string "slack_state"
    t.string "slack_status_emoji"
    t.string "slack_status_text"
    t.string "slack_title"
    t.string "slack_website"
    t.enum "status", default: "active", null: false, enum_type: "status"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["magic_link_token"], name: "index_users_on_magic_link_token", unique: true
    t.index ["manager_id"], name: "index_users_on_manager_id"
    t.index ["p_id"], name: "index_users_on_p_id", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "service_key_usages", "service_keys"
  add_foreign_key "service_keys", "services"
  add_foreign_key "service_keys", "users", column: "created_by_id"
  add_foreign_key "service_webhooks", "services"
  add_foreign_key "service_webhooks", "users", column: "created_by_id"
  add_foreign_key "services", "users", column: "created_by_id"
  add_foreign_key "user_sessions", "users"
  add_foreign_key "user_sessions", "users", column: "impersonated_by_id"
  add_foreign_key "users", "users", column: "manager_id"
end
