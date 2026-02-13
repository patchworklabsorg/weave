# frozen_string_literal: true

class ProfilePhotosController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :set_user

  def show
    # Redirect to avatar or initials based on whether user has uploaded photo
    if @user.cropped_image_data.present?
      redirect_to user_avatar_path(@user.p_id, :medium)
    else
      redirect_to user_initials_path(@user.p_id)
    end
  end

  def avatar
    variant = params[:variant] || "medium"

    if @user.cropped_image_data.blank?
      redirect_to user_initials_path(@user.p_id, variant)
      return
    end

    # TODO: Implement ActiveStorage variant generation
    # For now, redirect to initials
    redirect_to user_initials_path(@user.p_id, variant)
  end

  def avatar_square
    # TODO: Implement square avatar variant
    redirect_to user_initials_path(@user.p_id, params[:variant])
  end

  def avatar_circle
    # TODO: Implement circle avatar variant
    redirect_to user_initials_circle_path(@user.p_id, params[:variant])
  end

  def initials
    variant = params[:variant] || "medium"
    size = size_for_variant(variant)

    svg = generate_initials_svg(@user.initials, size)

    render inline: svg, content_type: "image/svg+xml"
  end

  def initials_circle
    variant = params[:variant] || "medium"
    size = size_for_variant(variant)

    svg = generate_initials_svg(@user.initials, size, circle: true)

    render inline: svg, content_type: "image/svg+xml"
  end

  private

  def set_user
    @user = User.find_by!(p_id: params[:p_id])
  end

  def size_for_variant(variant)
    case variant.to_s
    when "small" then 32
    when "medium" then 64
    when "large" then 128
    when "xlarge" then 256
    else 64
    end
  end

  def generate_initials_svg(initials, size, circle: false)
    # Generate a deterministic color based on initials
    hue = initials.bytes.sum % 360
    bg_color = "hsl(#{hue}, 70%, 50%)"

    font_size = size / 2

    <<~SVG
      <svg width="#{size}" height="#{size}" xmlns="http://www.w3.org/2000/svg">
        #{circle ? %(<circle cx="#{size/2}" cy="#{size/2}" r="#{size/2}" fill="#{bg_color}"/>) : %(<rect width="#{size}" height="#{size}" fill="#{bg_color}"/>)}
        <text
          x="50%"
          y="50%"
          dominant-baseline="central"
          text-anchor="middle"
          font-family="Arial, sans-serif"
          font-size="#{font_size}"
          font-weight="bold"
          fill="white"
        >#{initials.upcase}</text>
      </svg>
    SVG
  end
end
