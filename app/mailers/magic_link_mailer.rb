# frozen_string_literal: true

class MagicLinkMailer < ApplicationMailer
  def login_link(user)
    @user = user
    @magic_link_url = magic_link_login_url(token: user.magic_link_token)

    mail(
      to: @user.email,
      subject: "Your login link"
    )
  end

end
