# frozen_string_literal: true

# A deleted member's sealed envelope, waiting for the next reporting run to
# count it into DemographicDepartedTotal (see DemographicsVault.fold!). It has
# no link to a person and no timestamps. The reporting run deletes it.
# == Schema Information
#
# Table name: demographic_folds
# Database name: primary
#
#  id       :uuid             not null, primary key
#  cohorts  :jsonb            not null
#  envelope :text             not null
#  key_id   :string           not null
#
class DemographicFold < ApplicationRecord
  validates :envelope, :key_id, presence: true

  self.filter_attributes += %w[envelope]

end
