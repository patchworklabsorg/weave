# frozen_string_literal: true

# A named set of users. Groups are the unit of access: later, an OAuth app is
# opened to groups instead of to people one by one.
#
# A `manual` group is managed by hand in the admin panel. A `system` group is
# kept in sync from user attributes (staff, board, ...), so nobody may rename
# it, delete it, or change its members by hand.
#
# The slug is the stable name that relying parties see, so it never changes
# after the group is created. Renaming a group changes only its display name.
# == Schema Information
#
# Table name: groups
# Database name: primary
#
#  id            :bigint           not null, primary key
#  deleted_at    :datetime
#  description   :text
#  kind          :string           default("manual"), not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_groups_on_created_by_id  (created_by_id)
#  index_groups_on_deleted_at     (deleted_at)
#  index_groups_on_name           (name) UNIQUE WHERE (deleted_at IS NULL)
#  index_groups_on_slug           (slug) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Group < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :grp

  acts_as_paranoid
  has_paper_trail

  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  enum :kind, { manual: "manual", system: "system" }, default: "manual", validate: true

  belongs_to :created_by, class_name: "User", optional: true
  has_many :memberships, class_name: "Group::Membership", dependent: :destroy
  has_many :active_memberships, -> { active }, class_name: "Group::Membership", inverse_of: :group, dependent: nil
  has_many :users, through: :active_memberships
  has_many :application_access_grants, as: :grantee, dependent: :destroy

  before_validation :generate_slug, on: :create

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, length: { maximum: 64 }, format: { with: SLUG_FORMAT }
  validate :name_unique_among_live_groups
  validate :slug_unique_among_live_groups
  validate :slug_unchanged, on: :update
  validate :slug_not_reserved, if: :manual?

  def to_param = slug

  # Hand edits (rename, delete, member changes) are allowed on manual groups
  # only. System groups follow user attributes.
  def editable? = manual?

  private

  def generate_slug
    self.slug = name.to_s.parameterize if slug.blank?
  end

  # The unique indexes cover live rows only, so a deleted group frees its name
  # and slug. Check the same thing here to give a form error, not an exception.
  def name_unique_among_live_groups
    return if name.blank?
    return unless Group.where.not(id: id).exists?(["lower(name) = ?", name.downcase])

    errors.add(:name, :taken)
  end

  def slug_unique_among_live_groups
    return if slug.blank?
    return unless Group.where.not(id: id).exists?(slug: slug)

    errors.add(:slug, :taken)
  end

  # System group slugs belong to SystemGroups, even before the system group
  # exists, so a hand-made group can't take one and pick up synced members.
  def slug_not_reserved
    errors.add(:slug, "is reserved for a system group") if SystemGroups::SLUGS.include?(slug)
  end

  def slug_unchanged
    errors.add(:slug, "can't be changed after the group is created") if slug_changed?
  end

end
