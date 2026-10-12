# frozen_string_literal: true

# == Schema Information
#
# Table name: impersonation_actions
# Database name: primary
#
#  id                :bigint           not null, primary key
#  controller_action :string
#  http_method       :string           not null
#  params            :jsonb            not null
#  path              :string           not null
#  status            :integer
#  created_at        :datetime         not null
#  impersonation_id  :bigint           not null
#
# Indexes
#
#  index_impersonation_actions_on_impersonation_id  (impersonation_id)
#
# Foreign Keys
#
#  fk_rails_...  (impersonation_id => impersonations.id) ON DELETE => cascade
#
# One request an admin made while impersonating a user (see
# RecordsImpersonationActions). Only admins see these rows, under the
# impersonation on the admin user page.
# == Schema Information
#
# Table name: impersonation_actions
# Database name: primary
#
#  id                :bigint           not null, primary key
#  controller_action :string
#  http_method       :string           not null
#  params            :jsonb            not null
#  path              :string           not null
#  status            :integer
#  created_at        :datetime         not null
#  impersonation_id  :bigint           not null
#
# Indexes
#
#  index_impersonation_actions_on_impersonation_id  (impersonation_id)
#
# Foreign Keys
#
#  fk_rails_...  (impersonation_id => impersonations.id) ON DELETE => cascade
#
class Impersonation::Action < ApplicationRecord
  self.table_name = "impersonation_actions"

  belongs_to :impersonation

  validates :http_method, :path, presence: true

  scope :chronological, -> { order(:created_at, :id) }

  def state_changing?
    http_method != "GET"
  end

end
