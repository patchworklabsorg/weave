# frozen_string_literal: true

class ServiceSerializer
  def initialize(service, options = {})
    @service = service
    @options = options
  end

  def as_json
    base_attributes.tap do |json|
      json[:keys] = key_attributes if @options[:include_keys]
      json[:webhooks] = webhook_attributes if @options[:include_webhooks]
      json[:created_by] = UserSerializer.render(@service.created_by) if @options[:include_created_by]
    end
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  private

  def base_attributes
    {
      id: @service.id,
      name: @service.name,
      description: @service.description,
      status: @service.status,
      active: @service.active?,
      created_at: @service.created_at,
      updated_at: @service.updated_at
    }
  end

  def key_attributes
    @service.keys.map { |key| ServiceKeySerializer.new(key).as_json }
  end

  def webhook_attributes
    @service.webhooks.map { |webhook| ServiceWebhookSerializer.new(webhook).as_json }
  end

  class << self
    def render(service, options = {})
      new(service, options).as_json
    end

    def render_collection(services, options = {})
      services.map { |service| new(service, options).as_json }
    end
  end
end
