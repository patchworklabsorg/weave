# frozen_string_literal: true

# One patch: a grant program of Patchwork Labs, for example Project Ganymede.
#
# The slug is the stable name that apps see. It is the program key in
# config/kyc/knot.yml and the patch slug in Quilt, so it never changes after
# the patch is created: the model refuses the change, and a database trigger
# refuses it too. Renaming a patch changes only its display name.
#
# A patch has roles: the patch_lead governance role (config/roles.yml),
# scoped by the slug, and the roles a superadmin defines for the patch
# (PatchRole). It also has OAuth apps linked to it (oauth_applications.patch_id).
# The `patches` claim sends a person's patch roles to apps (see PatchRoles).
#
# There is no delete: role assignments, Quilt and app tokens name the slug.
# == Schema Information
#
# Table name: patches
# Database name: primary
#
#  id            :bigint           not null, primary key
#  description   :text
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_patches_on_created_by_id  (created_by_id)
#  index_patches_on_slug           (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Patch < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :ptch

  has_paper_trail

  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

  belongs_to :created_by, class_name: "User", optional: true
  has_many :applications, class_name: "Doorkeeper::Application", inverse_of: :patch, dependent: :restrict_with_exception
  has_many :roles, class_name: "PatchRole", inverse_of: :patch, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validates :slug, presence: true, length: { maximum: 64 }, format: { with: SLUG_FORMAT }, uniqueness: true
  validate :slug_unchanged, on: :update

  def to_param = slug

  # Creates a patch for each program in config/kyc/knot.yml, named as the
  # program. Idempotent. Never renames or removes a patch.
  #
  # model: the ActiveRecord class of the patches table (a migration passes
  # its own).
  def self.sync_programs!(model: self)
    KnotSettings.programs.each do |program|
      model.find_or_create_by!(slug: program.key) { |patch| patch.name = program.name }
    end
    model.where(slug: KnotSettings.program_keys).order(:slug).to_a
  end

  private

  def slug_unchanged
    errors.add(:slug, "can't be changed after the patch is created") if slug_changed?
  end

end
