# frozen_string_literal: true

# Storage for the OIDC `nonce` carried from the authorization request through to
# the id_token. Schema is dictated by doorkeeper-openid_connect
# (Doorkeeper::OpenidConnect::Request); do not add columns it does not know
# about.
class CreateDoorkeeperOpenidConnectTables < ActiveRecord::Migration[8.1]
  def change
    # rubocop:disable Rails/CreateTableWithTimestamps
    # Rows live and die with their access grant (ON DELETE CASCADE below) and
    # are consumed within the ~10 minute authorization code window, so there is
    # nothing for created_at/updated_at to tell us. The gem's model does not
    # declare them either.
    create_table :oauth_openid_requests do |t|
      # The foreign key is declared inline rather than as a follow-up
      # add_foreign_key: strong_migrations rejects the latter (it takes a lock
      # on the referenced table) but permits it here, because the table is
      # brand new and therefore empty and unreferenced.
      t.references :access_grant, null: false, index: true,
                   foreign_key: { to_table: :oauth_access_grants, on_delete: :cascade }
      t.string :nonce, null: false
    end
    # rubocop:enable Rails/CreateTableWithTimestamps
  end
end
