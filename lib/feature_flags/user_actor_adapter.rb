# frozen_string_literal: true

module FeatureFlags
  # Lets an admin add a user to an actor gate by any value that UserLookup knows:
  # an email, a public id, a Slack id, or a p_id in any letter case.
  #
  # Flipper matches a user only on the exact flipper_id (the p_id), but the
  # Flipper UI saves whatever the admin types. This adapter replaces the typed
  # value with the flipper_id of the user before the gate is saved. A value that
  # matches no user raises UnknownActor, because a gate that matches nobody does
  # nothing.
  #
  # Disable removes the typed value and the flipper_id of the user it names, and
  # never raises, so the remove button also clears a gate saved before this
  # adapter existed.
  class UserActorAdapter < Flipper::Adapters::Wrapper
    class UnknownActor < ArgumentError; end

    def enable(feature, gate, thing)
      return super unless gate.key == :actors
      # Code that passes a User already gives the correct flipper_id.
      return super if Groups.user_for(thing)

      user = UserLookup.call(thing.value)
      unless user
        raise UnknownActor,
              "#{thing.value.inspect} matches no user. Enter an email, a #{Weave.p_id_prefix} id, a usr_ id, or a Slack id."
      end

      super(feature, gate, Flipper::Types::Actor.new(user))
    end

    def disable(feature, gate, thing)
      if gate.key == :actors && !Groups.user_for(thing)
        user = UserLookup.call(thing.value)
        super(feature, gate, Flipper::Types::Actor.new(user)) if user && user.flipper_id != thing.value
      end

      super
    end

    # Sends the admin back to the add-actor form with the UnknownActor message,
    # which the form shows, instead of an error page. Flipper::UI escapes it.
    class UnknownActorRedirect
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue UnknownActor => e
        request = Rack::Request.new(env)
        [302, { "location" => "#{request.script_name}#{request.path_info}?#{Rack::Utils.build_query("error" => e.message)}" }, []]
      end

    end

  end
end
