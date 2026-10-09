# frozen_string_literal: true

# Records that a person accepted the code of conduct, from the /slack page or
# the Slack form (see Webhooks::SlackController#interactions).
#
# When the Slack import gave the person a placeholder name (User#name_missing?),
# they must also give their real name. The acceptance is recorded here, at
# once, so the next page they see is up to date. SlackCodeOfConductAcceptedJob
# then does the Slack side: it promotes a guest to full member, and it updates
# the Slack DM when one is given.
class CodeOfConductAcceptance
  Result = Data.define(:user, :errors) do
    def success? = errors.empty?
  end

  # first_name / last_name are read only when the user's name is missing.
  # message is the Slack DM to update, as { channel:, ts: }.
  def self.call(user, first_name: nil, last_name: nil, message: nil)
    new(user, first_name:, last_name:, message:).call
  end

  def initialize(user, first_name:, last_name:, message:)
    @user = user
    @first_name = first_name.to_s.strip
    @last_name = last_name.to_s.strip
    @message = message
  end

  def call
    if @user.name_missing?
      errors = name_errors
      return Result.new(user: @user, errors:) if errors.any?

      @user.update!(first_name: @first_name, last_name: @last_name)
    end

    @user.update_columns(slack_coc_accepted_at: Time.current) if @user.slack_coc_accepted_at.nil? # rubocop:disable Rails/SkipsModelValidations
    SlackCodeOfConductAcceptedJob.perform_later(@user.slack_id, **{ message: @message }.compact) if @user.slack_id.present?

    Result.new(user: @user, errors: {})
  end

  private

  # Keyed by field, so the Slack form can show each error next to its input.
  def name_errors
    errors = {}
    errors[:first_name] = "Enter your first name." if real_name_part(@first_name).nil?
    errors[:last_name] = "Enter your last name." if real_name_part(@last_name).nil?
    errors
  end

  def real_name_part(value)
    value.presence unless User::PLACEHOLDER_NAMES.include?(value)
  end

end
