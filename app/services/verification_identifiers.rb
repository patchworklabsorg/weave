# frozen_string_literal: true

# The identifiers on an ID that the Knot will need (see docs/KYC.md): document
# type, issuing country, document number, national identity number (where the
# country issues one), legal name and date of birth.
#
# Weave NEVER stores these values. The verifier types them at the decision.
# VerificationFlow.decide gives them to the subscribers of EVENT, inside the
# transaction of the decision, and then drops them. A subscriber that keeps
# anything must keep only a one-way hash. A subscriber that raises rolls back
# the decision.
#
#   ActiveSupport::Notifications.subscribe(VerificationIdentifiers::EVENT) do |event|
#     event.payload => { verification:, outcome:, identifiers: }
#   end
#
# #inspect and #to_s hide the values, so a log line or an error report can't
# show them.
#
# national_id_absent is the verifier's answer "this document does not show a
# national identity number". It is needed only when the issuing country has a
# lifetime number (KnotSettings.lifetime_national_id_countries) and the
# national_id field is empty. Weave does not store it.
VerificationIdentifiers = Data.define(:document_type, :issuing_country, :document_number, :national_id,
                                      :legal_name, :date_of_birth, :national_id_absent) do
  self::EVENT = "identifiers.verification"
  self::REQUIRED = %i[document_type issuing_country document_number legal_name date_of_birth].freeze

  def initialize(national_id_absent: false, **values)
    super(national_id_absent: national_id_absent == true, **values)
  end

  # From the decision form. Blank values become nil, and the date is parsed.
  def self.from_params(params)
    values = members.index_with { |key| params[key].to_s.strip.presence }
    values[:national_id_absent] = values[:national_id_absent] == "1"
    values[:issuing_country] = values[:issuing_country]&.upcase
    values[:date_of_birth] = Date.iso8601(values[:date_of_birth]) if values[:date_of_birth]
    new(**values)
  rescue Date::Error
    new(**values, date_of_birth: :invalid)
  end

  # Error messages by field. Empty when the identifiers can be used.
  def errors
    found = self.class::REQUIRED.select { |key| public_send(key).nil? }.index_with("is required")
    found[:issuing_country] = "must be a two-letter country code" if issuing_country && !issuing_country.match?(/\A[A-Z]{2}\z/)
    found[:document_type] = "is not a known document type" if document_type && Verification::DOCUMENT_TYPES.exclude?(document_type)
    found[:date_of_birth] = "is not a date" if date_of_birth == :invalid
    found[:national_id] = I18n.t("knot.errors.national_id_required") if national_id_missing?
    found
  end

  # The issuing country has a lifetime national number, the field is empty,
  # and the verifier did not confirm that the document does not show one.
  def national_id_missing?
    national_id.nil? && !national_id_absent && issuing_country.present? &&
      KnotSettings.lifetime_national_id_country?(issuing_country)
  end

  def valid? = errors.empty?

  def inspect = "#<VerificationIdentifiers [FILTERED]>"

  def to_s = inspect

end
