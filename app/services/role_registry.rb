# frozen_string_literal: true

# The role definitions and their grant rules, from config/roles.yml (see
# docs/KYC.md "Roles"). RoleGrants enforces the rules. The roles table holds
# one row for each definition (see .sync!).
#
# .validate! runs at boot (config/initializers/roles.rb). An unknown key, rule,
# precondition, required role or scope source raises ConfigError, so a typo
# never starts Weave with a rule that nobody checks.
module RoleRegistry
  PATH = Rails.root.join("config/roles.yml")

  class ConfigError < StandardError; end

  # The rules a role can have for grant or revoke. A proposal rule goes
  # through IdentityGovernance. An immediate rule applies at once.
  PROPOSAL_RULES = %w[owner_proposes_board_approves owner_proposes_all_board_approve].freeze
  IMMEDIATE_RULES = %w[owner any_owner admin owner_or_identity_lead].freeze
  RULES = (PROPOSAL_RULES + IMMEDIATE_RULES).freeze

  PRECONDITIONS = %w[verified_by_another adult].freeze
  SCOPE_SOURCES = %w[knot_programs].freeze

  # Code reads these roles by key, so the config must define each of them.
  REQUIRED_KEYS = %w[verifier identity_lead key_holder board staff contractor patch_lead].freeze

  ROLE_KEYS = %w[name description scopable scope_source requires grant revoke].freeze
  RULE_KEYS = %w[rule preconditions_at_proposal preconditions_at_approval].freeze
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  Rule = Data.define(:rule, :preconditions_at_proposal, :preconditions_at_approval) do
    def proposal? = PROPOSAL_RULES.include?(rule)

    def all_board? = rule == "owner_proposes_all_board_approve"
  end

  Definition = Data.define(:key, :name, :description, :scopable, :scope_source, :requires, :grant, :revoke) do
    def scopable? = scopable

    def rule_for(action) = action.to_s == "revoke" ? revoke : grant
  end

  class << self
    def definitions = @definitions ||= parse(load_file)

    delegate :keys, to: :definitions

    def fetch(key)
      definitions.fetch(key.to_s) { raise ArgumentError, "Unknown role #{key.inspect}. Known roles: #{keys.join(', ')}." }
    end

    def known?(key) = definitions.key?(key.to_s)

    def validate! = definitions && true

    # The valid scopes of a scopable role. Empty for a global role.
    def scopes_for(key)
      definition = fetch(key)
      return [] unless definition.scopable?

      case definition.scope_source
      when "knot_programs" then KnotSettings.program_keys
      else []
      end
    end

    # nil is the only valid scope of a global role. A scopable role needs a
    # scope from its source.
    def valid_scope?(key, scope)
      fetch(key).scopable? ? scopes_for(key).include?(scope.to_s) : scope.nil?
    end

    # Roles that require this one (revoked with it).
    def dependents_of(key) = definitions.values.select { |definition| definition.requires.include?(key.to_s) }.map(&:key)

    # Creates or updates one roles row for each definition. Idempotent. Never
    # deletes a row: a role removed from the config keeps its row, so the
    # history of its assignments stays readable.
    #
    # model: the ActiveRecord class of the roles table (a migration passes its
    # own).
    def sync!(model: Role)
      definitions.each_value do |definition|
        role = model.find_or_initialize_by(key: definition.key)
        role.assign_attributes(name: definition.name, description: definition.description,
                               scopable: definition.scopable, system: true)
        role.save! if role.changed?
      end
      model.where(key: keys).index_by(&:key)
    end

    # For specs that change the config.
    def reset! = @definitions = nil

    # Parses and checks a config hash (the "roles" key of the file).
    def parse(raw)
      raise ConfigError, "#{PATH}: the top level needs a \"roles\" key" unless raw.is_a?(Hash) && raw["roles"].is_a?(Hash)

      unknown_top = raw.keys - ["roles"]
      raise ConfigError, "#{PATH}: unknown top-level key(s) #{unknown_top.join(', ')}" if unknown_top.any?

      roles = raw["roles"]
      definitions = roles.to_h { |key, values| [key.to_s, parse_role(key.to_s, values)] }

      missing = REQUIRED_KEYS - definitions.keys
      raise ConfigError, "#{PATH}: missing role(s) #{missing.join(', ')}" if missing.any?

      definitions.each_value do |definition|
        unknown = definition.requires - definitions.keys
        raise ConfigError, "#{PATH}: role #{definition.key} requires unknown role(s) #{unknown.join(', ')}" if unknown.any?
        raise ConfigError, "#{PATH}: role #{definition.key} can't require itself" if definition.requires.include?(definition.key)
      end
      definitions.freeze
    end

    private

    def load_file = YAML.safe_load_file(PATH, aliases: false)

    def parse_role(key, values)
      where = "#{PATH}: role #{key}"
      raise ConfigError, "#{where}: the key must match #{KEY_FORMAT.source}" unless key.match?(KEY_FORMAT)
      raise ConfigError, "#{where}: needs a hash of settings" unless values.is_a?(Hash)

      unknown = values.keys.map(&:to_s) - ROLE_KEYS
      raise ConfigError, "#{where}: unknown key(s) #{unknown.join(', ')}" if unknown.any?

      %w[name grant revoke].each { |required| raise ConfigError, "#{where}: needs #{required}" if values[required].blank? }
      scopable = values.fetch("scopable", false)
      raise ConfigError, "#{where}: scopable must be true or false" unless [true, false].include?(scopable)

      scope_source = values["scope_source"]
      if scopable && !SCOPE_SOURCES.include?(scope_source)
        raise ConfigError, "#{where}: a scopable role needs scope_source, one of #{SCOPE_SOURCES.join(', ')}"
      end
      raise ConfigError, "#{where}: scope_source is only for a scopable role" if !scopable && scope_source

      requires = values.fetch("requires", [])
      raise ConfigError, "#{where}: requires must be a list of role keys" unless requires.is_a?(Array)

      Definition.new(key:, name: values["name"].to_s, description: values["description"].to_s, scopable:,
                     scope_source:, requires: requires.map(&:to_s).freeze,
                     grant: parse_rule("#{where} grant", values["grant"]), revoke: parse_rule("#{where} revoke", values["revoke"]))
    end

    def parse_rule(where, values)
      raise ConfigError, "#{where}: needs a hash with a rule" unless values.is_a?(Hash)

      unknown = values.keys.map(&:to_s) - RULE_KEYS
      raise ConfigError, "#{where}: unknown key(s) #{unknown.join(', ')}" if unknown.any?

      rule = values["rule"].to_s
      raise ConfigError, "#{where}: unknown rule #{rule.inspect}. Known rules: #{RULES.join(', ')}" unless RULES.include?(rule)

      at_proposal = preconditions("#{where} preconditions_at_proposal", values["preconditions_at_proposal"])
      at_approval = preconditions("#{where} preconditions_at_approval", values["preconditions_at_approval"])
      if (at_proposal.any? || at_approval.any?) && !PROPOSAL_RULES.include?(rule)
        raise ConfigError, "#{where}: preconditions need a proposal rule"
      end

      Rule.new(rule:, preconditions_at_proposal: at_proposal, preconditions_at_approval: at_approval)
    end

    def preconditions(where, values)
      list = Array(values).map(&:to_s)
      unknown = list - PRECONDITIONS
      raise ConfigError, "#{where}: unknown precondition(s) #{unknown.join(', ')}. Known: #{PRECONDITIONS.join(', ')}" if unknown.any?

      list.freeze
    end

  end
end
