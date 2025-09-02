# frozen_string_literal: true

class AddShippingNotesToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :shipping_notes, :text
  end

end
