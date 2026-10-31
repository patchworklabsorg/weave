# frozen_string_literal: true

# What the app launcher on the member dashboard shows for an OAuth app, and
# which group an approved access request adds the member to. Included into
# Doorkeeper::Application by config/initializers/oauth_application_public_id.rb.
#
# The launcher lists an app only when `show_in_launcher` is on and the app has
# a `launch_url`. A member sees the apps that AppAccess lets them use. An app
# with an `access_request_group` also shows to the members who may not use it
# yet, with a button to ask for access (see AccessRequests).
#
# The access request group must be a manual group that gives access to the
# app (an access grant or a role), or approval would add the member to a
# group that does not let them in.
module OauthApplicationLauncher
  extend ActiveSupport::Concern

  included do
    belongs_to :access_request_group, class_name: "Group", optional: true
    has_many :access_requests, dependent: nil, inverse_of: :application

    validates :launch_url, length: { maximum: 2000 }, allow_blank: true
    validates :launcher_icon_url, length: { maximum: 2000 }, allow_blank: true
    validates :launcher_description, length: { maximum: 280 }, allow_blank: true
    validate :launcher_urls_are_web_addresses
    validate :launch_url_present_for_launcher, if: :show_in_launcher
    validate :access_request_group_gives_access, if: -> { access_request_group_id.present? && will_save_change_to_access_request_group_id? }

    after_update_commit -> { AccessRequests.cancel_stale!(self) }, if: :saved_change_to_access_request_group_id?

    scope :in_launcher, -> { where(show_in_launcher: true).where.not(launch_url: [nil, ""]).order(:name) }
  end

  private

  # The icon is an <img> on a Weave page, so it must be https. The launch URL
  # may be http in development only.
  def launcher_urls_are_web_addresses
    errors.add(:launch_url, "must be an https URL") if launch_url.present? && !web_url?(launch_url, allow_http: !Rails.env.production?)
    errors.add(:launcher_icon_url, "must be an https URL") if launcher_icon_url.present? && !web_url?(launcher_icon_url, allow_http: false)
  end

  def web_url?(value, allow_http:)
    uri = URI.parse(value.to_s.strip)
    schemes = allow_http ? %w[https http] : %w[https]
    schemes.include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def launch_url_present_for_launcher
    errors.add(:launch_url, "is needed to show the app in the launcher") if launch_url.blank?
  end

  def access_request_group_gives_access
    group = access_request_group
    if group.nil? || !group.manual?
      errors.add(:access_request_group, "must be a manual group")
    elsif group.waives_code_of_conduct || group.waives_slack
      errors.add(:access_request_group, "can't be a sponsored project group that waives onboarding steps")
    elsif persisted? && !AppAccess.linked_groups(self).exists?(id: group.id)
      errors.add(:access_request_group, "must have access to the app (an access grant or a role)")
    end
  end

end
