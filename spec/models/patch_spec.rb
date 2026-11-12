# frozen_string_literal: true

require "rails_helper"

# A patch is a grant program. Apps, Quilt and role scopes name its slug, so the
# slug never changes.
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
RSpec.describe Patch do
  it "needs a name and a slug in the slug format" do
    expect(build(:patch, name: "")).not_to be_valid
    expect(build(:patch, slug: "")).not_to be_valid
    %w[Ganymede gany_mede -ganymede ganymede- gany--mede].each do |slug|
      expect(build(:patch, slug:)).not_to be_valid, "expected #{slug.inspect} to be refused"
    end
    expect(build(:patch, slug: "project-ganymede-2")).to be_valid
  end

  it "keeps the slug unique" do
    create(:patch, slug: "ganymede")

    expect(build(:patch, slug: "ganymede")).not_to be_valid
  end

  it "refuses a slug change, in the model and in the database" do
    patch = create(:patch, slug: "ganymede")

    expect(patch.update(slug: "europa")).to be(false)
    expect(patch.errors[:slug]).to include("can't be changed after the patch is created")
    expect { patch.update_column(:slug, "europa") }.to raise_error(ActiveRecord::StatementInvalid, /slug of a patch never changes/) # rubocop:disable Rails/SkipsModelValidations
  end

  it "refuses a bad slug in the database too" do
    sql = "INSERT INTO patches (slug, name, created_at, updated_at) VALUES ('Bad Slug', 'Bad', now(), now())"

    expect { ActiveRecord::Base.connection.execute(sql) }.to raise_error(ActiveRecord::StatementInvalid, /patches_slug_format/)
  end

  it "uses the slug in URLs" do
    expect(build(:patch, slug: "ganymede").to_param).to eq("ganymede")
  end

  it "keeps a version of each change" do
    patch = create(:patch, name: "Ganymede")
    patch.update!(name: "Project Ganymede")

    expect(patch.versions.map(&:event)).to eq(%w[create update])
  end

  describe ".sync_programs!" do
    it "creates a patch for each program in config/kyc/knot.yml, named as the program" do
      expect { described_class.sync_programs! }.to change(described_class, :count).by(KnotSettings.program_keys.size)

      expect(described_class.find_by!(slug: "ganymede").name).to eq("Project Ganymede")
      expect(described_class.pluck(:slug)).to match_array(KnotSettings.program_keys)
    end

    it "is idempotent and never renames a patch" do
      create(:patch, slug: "ganymede", name: "Ganymede (renamed)")

      expect { 2.times { described_class.sync_programs! } }.not_to change(described_class, :count)
      expect(described_class.find_by!(slug: "ganymede").name).to eq("Ganymede (renamed)")
    end
  end
end
