# frozen_string_literal: true

class HomeController < ApplicationController
  # before_action :authenticate_user
  skip_before_action :authenticate_user!, only: [:index]
  layout false

  def index
    # Signed-in members land on their account dashboard, not the
    # "you found the front door" splash (which is for anonymous visitors).
    redirect_to profile_path if current_user
  end

end
