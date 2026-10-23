# frozen_string_literal: true

# Live results for the ⌘K command bar: users, groups and OAuth apps that
# match the query. JSON only. The shape is the Patchwork standard for a
# command bar search endpoint (see internal-docs design/components.md):
# a flat list of { type, label, hint, path }.
class Admin::SearchController < Admin::BaseController
  LIMIT = 5

  def index
    query = params[:q].to_s.strip
    results = query.length >= 2 ? users(query) + groups(query) + applications(query) : []

    render json: results
  end

  private

  def users(query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    # Only users this admin may open (Admin::UsersController#show checks the
    # same thing), so no result is a dead end.
    User.where("first_name ILIKE :t OR last_name ILIKE :t OR email ILIKE :t OR p_id ILIKE :t", t: term)
        .order(:first_name, :last_name).limit(LIMIT * 3)
        .select { |user| UserAdminPermissions.new(current_user, user).view? }
        .first(LIMIT).map do |user|
      { type: "user", label: user.full_name, hint: user.email, path: admin_user_path(user) }
    end
  end

  def groups(query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    Group.where("name ILIKE :t OR slug ILIKE :t", t: term).order(:name).limit(LIMIT).map do |group|
      { type: "group", label: group.name, hint: group.slug, path: admin_group_path(group) }
    end
  end

  def applications(query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    Doorkeeper::Application.where("name ILIKE :t OR uid ILIKE :t", t: term).order(:name).limit(LIMIT).map do |application|
      { type: "application", label: application.name, hint: application.uid, path: admin_oauth_application_path(application) }
    end
  end

end
