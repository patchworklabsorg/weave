# frozen_string_literal: true

# The data-category registry: the nine categories of the v0.8 retention
# matrix (proposal section 06, "What delete actually deletes"). Every piece of
# data Weave holds about a member belongs to one category, and each category
# answers three questions: can the member export it, what happens to it on
# delete, and if it stays, under which obligation and for how long.
#
# Takeout (Takeout) and deletion (DeletionPipeline) both read this registry.
# The matrix is the acceptance criteria of the pipeline:
# spec/services/deletion_pipeline_matrix_spec.rb has one example per
# category.
#
# Outcomes:
# - deleted: destroyed at deletion (real deletion, not a soft delete).
# - folded: the generalized bands go into the delete-time aggregates, then
#   the record is destroyed.
# - retained: kept under the named obligation, without a link to the
#   account where possible, for the window in config/kyc/data_retention.yml.
#
# Member-facing names, obligations and windows are in
# config/locales/data_handling.en.yml under data_categories.<key>.
module DataCategories
  OUTCOMES = %w[deleted folded retained].freeze

  Category = Data.define(:key, :outcome, :source_models, :exportable) do
    def name = I18n.t("data_categories.#{key}.name")

    # The text key of the legal basis for keeping it (or for deleting it).
    def legal_basis_key = "data_categories.#{key}.legal_basis"

    def legal_basis = I18n.t(legal_basis_key, **window_values)

    def retained? = outcome == "retained"

    def window_values
      {
        audit_years: DataRetention.verification_audit_window.in_days.div(365),
        financial_years: DataRetention.financial_keep_years,
        image_days: VerificationSettings.purge_image_after_pass.in_days.to_i,
        guardian_age: DataRetention.guardian_contact_until_age
      }
    end
  end

  ALL = [
    Category.new(key: "raw_id_images", outcome: "deleted", exportable: false,
                 source_models: %w[Verification#id_document]),
    Category.new(key: "account_profile", outcome: "deleted", exportable: true,
                 source_models: %w[User EmailAddress UserAddress User::Session User::MagicLink User::Passkey Ahoy::Visit
                                   Ahoy::Message Group::Membership ApplicationAccessGrant ApplicationRoleAssignment
                                   Doorkeeper::AccessGrant Doorkeeper::AccessToken TakeoutRequest DormancyWarning
                                   ThreadCount::Entry FunderConsent PaperTrail::Version]),
    Category.new(key: "guardian_contact", outcome: "deleted", exportable: true,
                 source_models: %w[GuardianConsent]),
    Category.new(key: "demographics", outcome: "folded", exportable: false,
                 source_models: %w[DemographicRecord]),
    Category.new(key: "verification_audit", outcome: "retained", exportable: true,
                 source_models: %w[Verification VerificationEvent BreakGlassRecord]),
    Category.new(key: "financial", outcome: "retained", exportable: true,
                 source_models: %w[GrantDisbursement]),
    Category.new(key: "participation", outcome: "folded", exportable: true,
                 source_models: %w[ProgramParticipation]),
    Category.new(key: "funder_records", outcome: "retained", exportable: true,
                 source_models: %w[ProgramParticipation]),
    Category.new(key: "knot", outcome: "retained", exportable: false,
                 source_models: %w[Knot KnotHash ProgramGrant])
  ].freeze

  KEYS = ALL.map(&:key).freeze

  class << self
    def all = ALL

    def find(key) = ALL.find { |category| category.key == key.to_s } || raise(KeyError, "No data category #{key}")

    def exportable = ALL.select(&:exportable)

    def with_outcome(outcome) = ALL.select { |category| category.outcome == outcome.to_s }

  end
end
