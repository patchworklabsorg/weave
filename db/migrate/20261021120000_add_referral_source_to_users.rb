# frozen_string_literal: true

# How a new member found Patchwork, asked once on the signup form. Both are
# optional. See User::REFERRAL_SOURCES.
class AddReferralSourceToUsers < ActiveRecord::Migration[8.1]
  def change
    # Two nullable columns with no default: no table rewrite, no backfill.
    safety_assured do
      change_table :users, bulk: true do |t|
        t.string :referral_source
        t.string :referral_source_detail
      end
    end
  end

end
