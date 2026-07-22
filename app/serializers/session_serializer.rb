# frozen_string_literal: true

# == Schema Information
#
# Table name: sessions
# Database name: primary
#
#  id         :bigint           not null, primary key
#  data       :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  session_id :string           not null
#
# Indexes
#
#  index_sessions_on_session_id  (session_id) UNIQUE
#  index_sessions_on_updated_at  (updated_at)
#
class SessionSerializer
  def initialize(session)
    @session = session
  end

  def as_json
    {
      id: @session.id,
      device_info: @session.device_info,
      os_info: @session.os_info,
      ip_address: @session.ip_address,
      city: @session.city,
      state: @session.state,
      country: @session.country,
      timezone: @session.timezone,
      last_seen_at: @session.last_seen_at,
      created_at: @session.created_at,
      expires_at: @session.expires_at,
      impersonated: @session.impersonated_by_id.present?
    }
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  class << self
    def render(session)
      new(session).as_json
    end

    def render_collection(sessions)
      sessions.map { |session| new(session).as_json }
    end
  end
end
