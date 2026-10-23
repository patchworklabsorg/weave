# frozen_string_literal: true

class AddKnotToVerifications < ActiveRecord::Migration[8.1]
  def change
    # knot_id links each passed attempt to its Knot, so a returning member's
    # history reads as one chain. knot_review_reason is set when a Knot match
    # routes the pass to manual review with a second verifier. The table is
    # new in this release and has no rows, so the index and the foreign key do
    # not block writes.
    safety_assured do
      add_reference :verifications, :knot, foreign_key: { on_delete: :nullify }
      add_column :verifications, :knot_review_reason, :string
    end
  end

end
