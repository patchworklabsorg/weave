# frozen_string_literal: true

# Grant money paid to a member (financial / grant disbursement records,
# proposal section 06).
#
# Retained under a named obligation (IRS, audit, funder award terms). Weave
# keeps the record in full for financial.keep_years, or longer when a
# funder's terms say so: its financial_keep_years, or the end of its
# post-award window (config/kyc/data_retention.yml). The longest window
# wins. Then
# DataRetention::Sweeps anonymizes it: the person's details go, and the
# amount, the program and the year stay for ever.
#
# At account deletion the record stays under its obligation, but the link to
# the account goes (user_id). The payee details stay encrypted until the
# window ends.
# == Schema Information
#
# Table name: grant_disbursements
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  amount_cents           :integer          not null
#  anonymized_at          :datetime
#  currency               :string           default("USD"), not null
#  detached_at            :datetime
#  disbursed_on           :date             not null
#  funder                 :string
#  payee_email_ciphertext :text
#  payee_name_ciphertext  :text
#  program                :string           not null
#  reference_ciphertext   :text
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  user_id                :bigint
#
# Indexes
#
#  index_grant_disbursements_on_disbursed_on  (disbursed_on)
#  index_grant_disbursements_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class GrantDisbursement < ApplicationRecord
  has_encrypted :payee_name, :payee_email, :reference

  belongs_to :user, optional: true

  validates :program, inclusion: { in: ->(_) { KnotSettings.program_keys } }
  # A record keeps its own funder: one of the funders of its program.
  validates :funder, inclusion: { in: ->(record) { DataRetention.funders_for_program(record.program) } }, allow_blank: true
  validates :disbursed_on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }

  scope :not_anonymized, -> { where(anonymized_at: nil) }

  def funder_key = funder.presence || DataRetention.funder_for_program(program)

  delegate :year, to: :disbursed_on

  # The last day Weave keeps the record in full.
  def full_retention_ends_on = DataRetention.financial_retention_ends_on(disbursed_on, funder_key:, program:)

  def anonymized? = anonymized_at.present?

  # Removes the person's details. The amount, the program, the funder and the
  # year stay. The exact dates go: the payment date and the creation time move
  # to January 1 of their year, so a date can't point back to one person.
  def anonymize!
    update!(user: nil, payee_name: nil, payee_email: nil, reference: nil, anonymized_at: Time.current,
            detached_at: detached_at || Time.current, disbursed_on: disbursed_on.beginning_of_year,
            created_at: created_at.beginning_of_year)
  end

end
