# frozen_string_literal: true

# The sealed handoff of a break-glass grant to the requester (see BreakGlass
# and docs/KYC.md). The requester's browser makes a one-time X25519 key pair
# and sends only the public key. The second approval seals the image's data
# key to it. The requester opens it once, in the browser, within the handoff
# window. Weave then deletes the sealed key.
class AddSealedHandoffToBreakGlassRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :break_glass_records, :requester_public_key, :text
    add_column :break_glass_records, :handoff_sealed_key, :text
    add_column :break_glass_records, :handoff_expires_at, :datetime
    add_column :break_glass_records, :opened_at, :datetime
  end
end
