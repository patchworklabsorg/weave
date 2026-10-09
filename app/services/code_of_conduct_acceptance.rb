# frozen_string_literal: true

# Records that a person accepted the code of conduct, from the /slack page or
# the Slack form (see Webhooks::SlackController#interactions).
#
# When the Slack import gave the person a placeholder name (User#name_missing?),
# they must also give their preferred name. They can also give a legal name
# (only if it differs) and a Slack nickname (if they don't want their
# preferred name in Slack). The Slack profile then gets the nickname, or the
# preferred name (see PushSlackNameJob).
#
# The acceptance is recorded here, at once, so the next page they see is up
# to date. SlackCodeOfConductAcceptedJob then does the Slack side: it promotes
# a guest to full member, and it updates the Slack DM when one is given.
class CodeOfConductAcceptance
  Result = Data.define(:user, :errors) do
    def success? = errors.empty?
  end

  NAME_FIELDS = %i[first_name last_name legal_first_name legal_last_name slack_name].freeze

  # names holds the NAME_FIELDS. They are read only when the user's name is
  # missing. message is the Slack DM to update, as { channel:, ts: }.
  def self.call(user, names: {}, message: nil)
    new(user, names:, message:).call
  end

  def initialize(user, names:, message:)
    @user = user
    @names = NAME_FIELDS.index_with { |field| names[field].to_s.strip }
    @message = message
  end

  def call
    if @user.name_missing?
      errors = name_errors
      return Result.new(user: @user, errors:) if errors.any?

      save_names
    end

    @user.update_columns(slack_coc_accepted_at: Time.current) if @user.slack_coc_accepted_at.nil? # rubocop:disable Rails/SkipsModelValidations
    SlackCodeOfConductAcceptedJob.perform_later(@user.slack_id, **{ message: @message }.compact) if @user.slack_id.present?

    Result.new(user: @user, errors: {})
  end

  private

  # Keyed by field, so the Slack form can show each error next to its input.
  def name_errors
    errors = {}
    errors[:first_name] = "Enter your preferred first name." if real_name_part(@names[:first_name]).nil?
    errors[:last_name] = "Enter your preferred last name." if real_name_part(@names[:last_name]).nil?
    if @names[:legal_first_name].present? ^ @names[:legal_last_name].present?
      errors[@names[:legal_first_name].present? ? :legal_last_name : :legal_first_name] = "Enter both parts of your legal name, or leave both blank."
    end
    errors[:slack_name] = "Use 80 characters or fewer." if @names[:slack_name].length > 80
    errors
  end

  def real_name_part(value)
    value.presence unless User::PLACEHOLDER_NAMES.include?(value)
  end

  def save_names
    @user.update!(
      first_name: @names[:first_name],
      last_name: @names[:last_name],
      legal_first_name: @names[:legal_first_name].presence,
      legal_last_name: @names[:legal_last_name].presence
    )
    PushSlackNameJob.perform_later(@user.id, nickname: @names[:slack_name].presence) if @user.slack_id.present?
  end

end
