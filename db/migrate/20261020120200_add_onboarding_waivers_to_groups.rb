# frozen_string_literal: true

# Per-project onboarding requirements. A group for a sponsored project (for
# example HackBoston) can waive the Patchwork code of conduct and the
# Patchwork Slack for its members.
class AddOnboardingWaiversToGroups < ActiveRecord::Migration[8.1]
  def change
    change_table :groups, bulk: true do |t|
      t.boolean :waives_code_of_conduct, default: false, null: false
      t.boolean :waives_slack, default: false, null: false
    end
  end

end
