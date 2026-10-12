# frozen_string_literal: true

module FeatureFlags
  # Gives the Flipper UI a label for each actor on a feature page.
  #
  # The UI passes the raw gate values here. A gate that holds a p_id gets the
  # email of its user. A gate that holds anything else never matches a user, so
  # its label says so and names the p_id to enter instead. UserActorAdapter
  # converts new gates, so only gates saved before it get that label.
  module ActorNames
    # Returns { gate value => label } for the values that have a label.
    def self.call(actor_ids)
      names = User.where(p_id: actor_ids).to_h { |user| [user.flipper_id, user.email] }

      actor_ids.each do |value|
        next if names.key?(value) || value.match?(User.p_id_format)

        user = UserLookup.call(value)
        names[value] = "NOT MATCHED: enter #{user ? "#{user.flipper_id} for #{user.email}" : "an email or a #{Weave.p_id_prefix} id"}"
      end

      names
    end
  end
end
