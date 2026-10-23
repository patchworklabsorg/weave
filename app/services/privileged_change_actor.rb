# frozen_string_literal: true

# Tells the permanent log (PrivilegedAttributeChange) who acts. The trigger on
# users reads the weave.actor_id and weave.actor_label settings of the
# database session.
#
# - ApplicationController sets them for each request (the signed-in user) and
#   restores them after the request.
# - IdentityGovernance sets them for each action that has an actor.
# - ApplicationJob sets the label to the job class.
# - A console session sets the label to the Console1984 user name
#   (config/initializers/console.rb).
#
# The settings are on the database session (set_config with is_local false),
# so they also hold outside a transaction. .with restores the earlier values
# after the block, so nothing leaks to the next request on the connection.
module PrivilegedChangeActor
  ID = "weave.actor_id"
  LABEL = "weave.actor_label"

  class << self
    def with(actor: nil, label: nil)
      previous = current
      set!(actor:, label:)
      yield
    ensure
      restore!(previous) if previous
    end

    def set!(actor: nil, label: nil)
      write(actor&.id.to_s, (label || label_for(actor)).to_s)
    end

    def clear! = write("", "")

    # [actor_id, actor_label] of this database session, as strings.
    def current
      connection.select_rows("SELECT current_setting('#{ID}', true), current_setting('#{LABEL}', true)").first
    end

    private

    def label_for(actor) = actor ? "user #{actor.p_id}" : ""

    # A failed restore must not hide the error of the block.
    def restore!(values)
      write(values[0].to_s, values[1].to_s)
    rescue ActiveRecord::StatementInvalid => error
      Rails.logger.warn("PrivilegedChangeActor could not restore the actor: #{error.class}")
    end

    def write(id, label)
      connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT set_config(?, ?, false), set_config(?, ?, false)", ID, id, LABEL, label])
      )
    end

    def connection = ActiveRecord::Base.connection

  end
end
