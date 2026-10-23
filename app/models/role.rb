# frozen_string_literal: true

# == Schema Information
#
# Table name: roles
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  key         :string           not null
#  name        :string           not null
#  scopable    :boolean          default(FALSE), not null
#  system      :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_roles_on_key  (key) UNIQUE
#
# One staff or identity role (see RoleRegistry and docs/KYC.md "Roles"). The
# rows come from config/roles.yml: RoleRegistry.sync! creates and updates them.
# Assignments are UserRole rows.
class Role < ApplicationRecord
  has_many :user_roles, dependent: :restrict_with_exception

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  # The row of a role key. Creates the rows from the config when the table
  # does not have it yet (a fresh database loaded from db/schema.rb has no
  # data rows).
  def self.fetch!(key)
    key = key.to_s
    RoleRegistry.fetch(key)
    find_by(key:) || RoleRegistry.sync!.fetch(key)
  end

  def definition = RoleRegistry.fetch(key)

end
