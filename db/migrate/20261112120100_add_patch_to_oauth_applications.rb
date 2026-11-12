# frozen_string_literal: true

# An OAuth app can belong to one patch (see Patch). Introspection names the
# patch of an app token (see config/initializers/doorkeeper.rb).
class AddPatchToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    # oauth_applications holds a few dozen rows, so the index and the foreign
    # key take no time and block nothing.
    safety_assured do
      add_reference :oauth_applications, :patch, foreign_key: true, index: true
    end
  end

end
