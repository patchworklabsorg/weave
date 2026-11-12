# frozen_string_literal: true

# Patches: the grant programs of Patchwork Labs, for example Project Ganymede
# (see Patch and docs/OAUTH.md "Patch claims").
#
# - The slug is the stable name that apps see. It matches the program key in
#   config/kyc/knot.yml and the patch slug in Quilt. A check constraint holds
#   the format, and a trigger refuses a change to it after the insert.
# - The migration creates one patch for each program in config/kyc/knot.yml
#   (Patch.sync_programs!). Seeds and `bin/rails patches:sync` do the same.
#
# db/schema.rb holds the function and the trigger through the fx gem.
class CreatePatches < ActiveRecord::Migration[8.1]
  # The migration's own model, so a later change to Patch can't break it.
  class MigrationPatch < ActiveRecord::Base
    self.table_name = "patches"
  end

  def up
    create_table :patches do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :patches, :slug, unique: true
    add_check_constraint :patches, "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'", name: "patches_slug_format"

    safety_assured do
      execute <<~SQL
        CREATE FUNCTION refuse_patch_slug_change() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog AS $$
        BEGIN
          IF NEW.slug IS DISTINCT FROM OLD.slug THEN
            RAISE EXCEPTION 'patches: the slug of a patch never changes';
          END IF;
          RETURN NEW;
        END;
        $$;
      SQL

      execute <<~SQL
        CREATE TRIGGER patches_slug_fixed
        BEFORE UPDATE OF slug ON patches
        FOR EACH ROW EXECUTE FUNCTION refuse_patch_slug_change();
      SQL
    end

    MigrationPatch.reset_column_information
    Patch.sync_programs!(model: MigrationPatch)
  end

  def down
    safety_assured do
      execute "DROP TRIGGER IF EXISTS patches_slug_fixed ON patches"
      execute "DROP FUNCTION IF EXISTS refuse_patch_slug_change()"
    end
    drop_table :patches
  end

end
