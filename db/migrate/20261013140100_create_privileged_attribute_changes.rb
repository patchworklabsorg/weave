# frozen_string_literal: true

# The permanent log of privileged user attributes (see PrivilegedAttributeChange
# and docs/KYC.md "The permanent log").
#
# A Postgres trigger on users writes one row for each change to is_board,
# identity_team, identity_key_holder, identity_lead or role. The trigger is in
# the database, so it also catches console writes, update_column and raw SQL.
# A second trigger refuses UPDATE, DELETE and TRUNCATE on the log table. The
# rows have no foreign key to users, so the deletion of an account keeps them.
#
# db/schema.rb holds the functions and triggers through the fx gem, so
# db:schema:load (tests, fresh databases) creates them too.
class CreatePrivilegedAttributeChanges < ActiveRecord::Migration[8.1]
  def up
    create_table :privileged_attribute_changes do |t|
      # No foreign key: the row stays after the account is deleted.
      t.bigint :user_id, null: false
      t.string :user_p_id
      t.string :attribute_name, null: false
      t.text :old_value
      t.text :new_value
      t.string :operation, null: false
      t.datetime :changed_at, null: false, default: -> { "now()" }
      t.string :db_user, null: false
      t.bigint :actor_id
      t.string :actor_label
    end
    add_index :privileged_attribute_changes, :user_id
    add_index :privileged_attribute_changes, :changed_at

    safety_assured do
      execute <<~SQL
        CREATE FUNCTION log_privileged_attribute_changes() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog AS $$
        DECLARE
          column_name text;
          old_text text;
          new_text text;
          actor_id_text text := nullif(current_setting('weave.actor_id', true), '');
          actor_label_text text := nullif(current_setting('weave.actor_label', true), '');
        BEGIN
          FOREACH column_name IN ARRAY ARRAY['is_board', 'identity_team', 'identity_key_holder', 'identity_lead', 'role'] LOOP
            new_text := to_jsonb(NEW) ->> column_name;
            IF TG_OP = 'INSERT' THEN
              old_text := NULL;
              CONTINUE WHEN new_text IS NULL OR new_text IN ('false', '0');
            ELSE
              old_text := to_jsonb(OLD) ->> column_name;
              CONTINUE WHEN old_text IS NOT DISTINCT FROM new_text;
            END IF;

            INSERT INTO public.privileged_attribute_changes
              (user_id, user_p_id, attribute_name, old_value, new_value, operation, changed_at, db_user, actor_id, actor_label)
            VALUES
              (NEW.id, NEW.p_id, column_name, old_text, new_text, lower(TG_OP), now(), CURRENT_USER,
               CASE WHEN actor_id_text ~ '^[0-9]+$' THEN actor_id_text::bigint END, actor_label_text);
          END LOOP;
          RETURN NULL;
        END;
        $$;
      SQL

      execute <<~SQL
        CREATE FUNCTION refuse_privileged_attribute_change_edits() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog AS $$
        BEGIN
          RAISE EXCEPTION 'privileged_attribute_changes is append-only: % is not allowed', TG_OP;
        END;
        $$;
      SQL

      execute <<~SQL
        CREATE TRIGGER log_privileged_attribute_changes
        AFTER INSERT OR UPDATE OF is_board, identity_team, identity_key_holder, identity_lead, role ON users
        FOR EACH ROW EXECUTE FUNCTION log_privileged_attribute_changes();
      SQL

      execute <<~SQL
        CREATE TRIGGER privileged_attribute_changes_append_only
        BEFORE UPDATE OR DELETE ON privileged_attribute_changes
        FOR EACH ROW EXECUTE FUNCTION refuse_privileged_attribute_change_edits();
      SQL

      execute <<~SQL
        CREATE TRIGGER privileged_attribute_changes_no_truncate
        BEFORE TRUNCATE ON privileged_attribute_changes
        FOR EACH STATEMENT EXECUTE FUNCTION refuse_privileged_attribute_change_edits();
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TRIGGER IF EXISTS log_privileged_attribute_changes ON users"
      execute "DROP TRIGGER IF EXISTS privileged_attribute_changes_append_only ON privileged_attribute_changes"
      execute "DROP TRIGGER IF EXISTS privileged_attribute_changes_no_truncate ON privileged_attribute_changes"
      execute "DROP FUNCTION IF EXISTS log_privileged_attribute_changes()"
      execute "DROP FUNCTION IF EXISTS refuse_privileged_attribute_change_edits()"
    end
    drop_table :privileged_attribute_changes
  end
end
