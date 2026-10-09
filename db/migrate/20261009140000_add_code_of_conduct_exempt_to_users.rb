# frozen_string_literal: true

class AddCodeOfConductExemptToUsers < ActiveRecord::Migration[8.1]
  def change
    # An admin can let one user use apps without accepting the code of conduct
    # (see AppAccess). Exempt users are not asked to accept or demoted.
    add_column :users, :code_of_conduct_exempt, :boolean, default: false, null: false
  end
end
