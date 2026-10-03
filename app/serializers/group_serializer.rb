# frozen_string_literal: true

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
#  fk_rails_...  (created_by_id => users.id)
#
class GroupSerializer
  def initialize(group, options = {})
    @group = group
    @options = options
  end

  def as_json
    {
      id: @group.public_id,
      name: @group.name,
      slug: @group.slug,
      description: @group.description,
      kind: @group.kind,
      created_at: @group.created_at,
      updated_at: @group.updated_at
    }
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  class << self
    def render(group, options = {})
      new(group, options).as_json
    end

    def render_collection(groups, options = {})
      groups.map { |group| new(group, options).as_json }
    end

  end

end
