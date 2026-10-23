# frozen_string_literal: true

# The demographics vault (see DemographicsVault and docs/KYC.md). The app
# writes sealed envelopes and never reads them back. Only the reporting run,
# which holds the private key, opens them, and it writes only aggregates.
class CreateDemographicsVault < ActiveRecord::Migration[8.0]
  def change
    # One sealed envelope per member. No column holds an answer.
    create_table :demographic_records do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :envelope, null: false
      t.string :key_id, null: false
      t.timestamps
    end

    # Envelopes of deleted members, waiting for the next reporting run to
    # count them into the departed totals. No link to a person and no
    # timestamps. A random id, so the row order does not tell when (and so
    # for whom) a row was added.
    create_table :demographic_folds, id: :uuid do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.text :envelope, null: false
      t.string :key_id, null: false
      t.jsonb :cohorts, null: false, default: []
    end

    # Running totals for departed members, per cohort. One row, sealed like
    # the answers: the totals are raw counts, so only the reporting run (with
    # the private key) can read them, and it shows them only after
    # small-count suppression.
    create_table :demographic_departed_totals do |t|
      t.text :envelope, null: false
      t.string :key_id, null: false
      t.timestamps
    end

    # The output of each reporting run, after small-count suppression.
    create_table :demographic_reports do |t|
      t.datetime :generated_at, null: false
      t.integer :threshold, null: false
      t.jsonb :results, null: false, default: {}
      t.integer :unreadable_count, null: false, default: 0
      t.integer :folds_counted, null: false, default: 0
      t.string :run_by
      t.timestamps
    end
    add_index :demographic_reports, :generated_at
  end

end
