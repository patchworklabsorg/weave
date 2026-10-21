# frozen_string_literal: true

# Links a user to their Active Directory account after any sign-in (magic
# link, passkey or password), so the sign-in page offers the password field
# from then on. Does nothing when AD is off, when the user is linked already,
# or when AD has no account for them. See DirectoryPasswords.
class LinkDirectoryAccountJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil? || DirectoryPasswords.linked?(user)

    DirectoryPasswords.link(user)
  end

end
