# frozen_string_literal: true

class NotifyOpsOnSecurityIncidentJob < ApplicationJob
  queue_as :urgent

  def perform(email:, input_type:, malicious_input:, ip_address:, user_agent:)
    # Notify ops team about potential security incident
    Rails.logger.warn "SECURITY INCIDENT: #{input_type} from #{email} (IP: #{ip_address})"
    Rails.logger.warn "Malicious input detected: #{malicious_input}"
    Rails.logger.warn "User agent: #{user_agent}"

    # TODO: Implement real notification system
    # - Send to Slack #security channel
    # - Email security team
    # - Create incident in PagerDuty/Sentry
    # SlackService.notify_channel('#security', security_alert_message(email, input_type, ip_address))
  end

  private

  def security_alert_message(email, input_type, ip_address)
    "🚨 Security Alert: Potential attack detected\n" \
    "Email: #{email}\n" \
    "Input Type: #{input_type}\n" \
    "IP: #{ip_address}\n" \
    "Investigate immediately!"
  end

end
