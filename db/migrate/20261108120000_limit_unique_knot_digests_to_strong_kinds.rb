# frozen_string_literal: true

# A birth digest (name, birth date and country of birth, see KnotHasher) can
# be on many Knots, like a soft digest: two verifiers can record that a match
# is a different person. Only the strong kinds stay unique.
class LimitUniqueKnotDigestsToStrongKinds < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :knot_hashes, %i[kind digest], unique: true, algorithm: :concurrently,
                                             name: "index_knot_hashes_on_strong_digest_kinds",
                                             where: "kind IN ('document', 'national_id')"
    remove_index :knot_hashes, name: "index_knot_hashes_on_strong_digest", algorithm: :concurrently
  end

  def down
    add_index :knot_hashes, %i[kind digest], unique: true, algorithm: :concurrently,
                                             name: "index_knot_hashes_on_strong_digest",
                                             where: "kind <> 'soft'"
    remove_index :knot_hashes, name: "index_knot_hashes_on_strong_digest_kinds", algorithm: :concurrently
  end

end
