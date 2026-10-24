# frozen_string_literal: true

class AddDelaySignOffToBreakGlassNotices < ActiveRecord::Migration[8.1]
  def change
    # A fraud investigation delay of a member notice needs the sign-off of a
    # second identity team member before it holds the notice (see
    # BreakGlass.sign_off_delay). The table is new in this release and has no
    # rows, so the index and the foreign key do not block writes.
    safety_assured do
      add_column :break_glass_notices, :delay_signed_off_at, :datetime
      add_reference :break_glass_notices, :delay_signed_off_by, foreign_key: { to_table: :users, on_delete: :nullify }
    end
  end

end
