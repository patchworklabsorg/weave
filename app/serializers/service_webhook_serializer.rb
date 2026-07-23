# frozen_string_literal: true

class ServiceWebhookSerializer
  def initialize(webhook, options = {})
    @webhook = webhook
    @options = options
  end

  def as_json
    base_attributes.tap do |json|
      json[:secret_token] = @webhook.secret_token if @options[:include_secret]
    end
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  private

  def base_attributes
    {
      id: @webhook.id,
      url: @webhook.url,
      event_type: @webhook.event_type,
      status: @webhook.status,
      active: @webhook.active?,
      last_triggered_at: @webhook.last_triggered_at,
      failure_count: @webhook.failure_count,
      created_at: @webhook.created_at,
      updated_at: @webhook.updated_at
    }
  end

  class << self
    def render(webhook, options = {})
      new(webhook, options).as_json
    end

    def render_collection(webhooks, options = {})
      webhooks.map { |webhook| new(webhook, options).as_json }
    end

  end

end
