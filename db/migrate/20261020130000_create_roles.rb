# frozen_string_literal: true

# Staff and identity roles move from boolean columns on users to a table (see
# RoleRegistry, RoleGrants and docs/KYC.md "Roles").
#
# - roles: one row for each definition in config/roles.yml.
# - user_roles: one row for each assignment. A row is never deleted: a revoke
#   sets revoked_at. A partial unique index allows one active assignment of a
#   role and scope for each person.
# - A trigger on user_roles writes each grant (insert) and each revoke (the
#   update that sets revoked_at) to the permanent log
#   (privileged_attribute_changes), with the role key and scope.
# - A second trigger refuses DELETE, TRUNCATE and every UPDATE of user_roles
#   except a revoke (revoked_at, revoked_by_id and revoke_reason, once) and the
#   foreign keys that the database empties when a user or proposal goes.
# - The users trigger now logs only role (the admin tier). The old boolean
#   columns stay for now, but Weave no longer writes them.
#
# db/schema.rb holds the functions and triggers through the fx gem.
class CreateRoles < ActiveRecord::Migration[8.1]
  def up
    create_table :roles do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :scopable, null: false, default: false
      t.boolean :system, null: false, default: false
      t.timestamps
    end
    add_index :roles, :key, unique: true

    create_table :user_roles do |t|
      # Nullable: the database empties it when the account is deleted, and
      # the row stays as history.
      t.references :user, foreign_key: { on_delete: :nullify }, index: true
      t.references :role, null: false, foreign_key: true, index: true
      t.string :scope
      t.references :granted_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.datetime :granted_at, null: false
      t.text :reason
      t.references :identity_governance_proposal, foreign_key: { on_delete: :nullify }, index: true
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.text :revoke_reason
      t.datetime :created_at, null: false, default: -> { "now()" }
    end
    add_index :user_roles, "user_id, role_id, COALESCE(scope, '')", unique: true, where: "revoked_at IS NULL",
                                                                     name: "index_user_roles_one_active_assignment"
    add_index :user_roles, [:role_id, :scope], where: "revoked_at IS NULL", name: "index_user_roles_active_by_role"
    add_check_constraint :user_roles, "revoked_at IS NOT NULL OR (revoked_by_id IS NULL AND revoke_reason IS NULL)",
                         name: "user_roles_revoke_fields_need_revoked_at"

    # A patch lead proposal names the program.
    add_column :identity_governance_proposals, :scope, :string

    # The permanent log names the role of a grant or revoke.
    add_column :privileged_attribute_changes, :role_key, :string
    add_column :privileged_attribute_changes, :role_scope, :string
    add_column :privileged_attribute_changes, :user_role_id, :bigint

    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION log_privileged_attribute_changes() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog AS $$
        DECLARE
          column_name text;
          old_text text;
          new_text text;
          actor_id_text text := nullif(current_setting('weave.actor_id', true), '');
          actor_label_text text := nullif(current_setting('weave.actor_label', true), '');
        BEGIN
          FOREACH column_name IN ARRAY ARRAY['role'] LOOP
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

      execute "DROP TRIGGER log_privileged_attribute_changes ON users"
      execute <<~SQL
        CREATE TRIGGER log_privileged_attribute_changes
        AFTER INSERT OR UPDATE OF role ON users
        FOR EACH ROW EXECUTE FUNCTION log_privileged_attribute_changes();
      SQL

      execute <<~SQL
        CREATE FUNCTION log_user_role_changes() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog AS $$
        DECLARE
          actor_id_text text := nullif(current_setting('weave.actor_id', true), '');
          actor_label_text text := nullif(current_setting('weave.actor_label', true), '');
          role_key_text text;
          p_id_text text;
          operation_text text;
        BEGIN
          IF TG_OP = 'INSERT' THEN
            operation_text := 'grant';
          ELSIF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
            operation_text := 'revoke';
          ELSE
            RETURN NULL;
          END IF;

          SELECT key INTO role_key_text FROM public.roles WHERE id = NEW.role_id;
          SELECT p_id INTO p_id_text FROM public.users WHERE id = NEW.user_id;

          INSERT INTO public.privileged_attribute_changes
            (user_id, user_p_id, attribute_name, old_value, new_value, operation, changed_at, db_user, actor_id, actor_label,
             role_key, role_scope, user_role_id)
          VALUES
            (COALESCE(NEW.user_id, 0), p_id_text,
             'role:' || role_key_text || COALESCE('[' || NEW.scope || ']', ''),
             CASE WHEN operation_text = 'grant' THEN 'false' ELSE 'true' END,
             CASE WHEN operation_text = 'grant' THEN 'true' ELSE 'false' END,
             operation_text, now(), CURRENT_USER,
             CASE WHEN actor_id_text ~ '^[0-9]+$' THEN actor_id_text::bigint END, actor_label_text,
             role_key_text, NEW.scope, NEW.id);
          RETURN NULL;
        END;
        $$;
      SQL

      execute <<~SQL
        CREATE FUNCTION refuse_user_role_edits() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog AS $$
        BEGIN
          IF TG_OP <> 'UPDATE' THEN
            RAISE EXCEPTION 'user_roles rows are permanent: % is not allowed. Revoke a role by setting revoked_at.', TG_OP;
          END IF;

          IF NEW.id IS DISTINCT FROM OLD.id
             OR NEW.role_id IS DISTINCT FROM OLD.role_id
             OR NEW.scope IS DISTINCT FROM OLD.scope
             OR NEW.granted_at IS DISTINCT FROM OLD.granted_at
             OR NEW.reason IS DISTINCT FROM OLD.reason
             OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'user_roles: only a revoke can change a row';
          END IF;

          -- The database empties these foreign keys when the row they point
          -- to goes. Nothing else may change them.
          IF (NEW.user_id IS DISTINCT FROM OLD.user_id AND NEW.user_id IS NOT NULL)
             OR (NEW.granted_by_id IS DISTINCT FROM OLD.granted_by_id AND NEW.granted_by_id IS NOT NULL)
             OR (NEW.identity_governance_proposal_id IS DISTINCT FROM OLD.identity_governance_proposal_id
                 AND NEW.identity_governance_proposal_id IS NOT NULL) THEN
            RAISE EXCEPTION 'user_roles: only a revoke can change a row';
          END IF;

          IF OLD.revoked_at IS NOT NULL THEN
            IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
               OR NEW.revoke_reason IS DISTINCT FROM OLD.revoke_reason
               OR (NEW.revoked_by_id IS DISTINCT FROM OLD.revoked_by_id AND NEW.revoked_by_id IS NOT NULL) THEN
              RAISE EXCEPTION 'user_roles: the role is already revoked';
            END IF;
          END IF;

          RETURN NEW;
        END;
        $$;
      SQL

      execute <<~SQL
        CREATE TRIGGER log_user_role_changes
        AFTER INSERT OR UPDATE OF revoked_at ON user_roles
        FOR EACH ROW EXECUTE FUNCTION log_user_role_changes();
      SQL

      execute <<~SQL
        CREATE TRIGGER user_roles_append_only
        BEFORE UPDATE OR DELETE ON user_roles
        FOR EACH ROW EXECUTE FUNCTION refuse_user_role_edits();
      SQL

      execute <<~SQL
        CREATE TRIGGER user_roles_no_truncate
        BEFORE TRUNCATE ON user_roles
        FOR EACH STATEMENT EXECUTE FUNCTION refuse_user_role_edits();
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TRIGGER IF EXISTS log_user_role_changes ON user_roles"
      execute "DROP TRIGGER IF EXISTS user_roles_append_only ON user_roles"
      execute "DROP TRIGGER IF EXISTS user_roles_no_truncate ON user_roles"
      execute "DROP FUNCTION IF EXISTS log_user_role_changes()"
      execute "DROP FUNCTION IF EXISTS refuse_user_role_edits()"

      execute "DROP TRIGGER log_privileged_attribute_changes ON users"
      execute <<~SQL
        CREATE OR REPLACE FUNCTION log_privileged_attribute_changes() RETURNS trigger
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
        CREATE TRIGGER log_privileged_attribute_changes
        AFTER INSERT OR UPDATE OF is_board, identity_team, identity_key_holder, identity_lead, role ON users
        FOR EACH ROW EXECUTE FUNCTION log_privileged_attribute_changes();
      SQL
    end

    remove_column :privileged_attribute_changes, :user_role_id
    remove_column :privileged_attribute_changes, :role_scope
    remove_column :privileged_attribute_changes, :role_key
    remove_column :identity_governance_proposals, :scope
    # The triggers above are gone, so the rows can go with the table.
    drop_table :user_roles
    drop_table :roles
  end
end
