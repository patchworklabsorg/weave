# frozen_string_literal: true

# The authorize request a magic link was asked for in, so the link resumes it
# even when it is opened in another browser. See User::MagicLink.
class AddReturnToToUserMagicLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :user_magic_links, :return_to, :string
  end

end
