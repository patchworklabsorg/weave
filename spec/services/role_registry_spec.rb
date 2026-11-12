# frozen_string_literal: true

require "rails_helper"

# The role definitions and their grant rules, from config/roles.yml.
RSpec.describe RoleRegistry do
  def file = YAML.safe_load_file(described_class::PATH)

  # The real file with one change.
  def changed(&block)
    raw = file
    block.call(raw["roles"])
    raw
  end

  delegate :parse, to: :described_class

  it "loads every role of the locked set from config/roles.yml" do
    expect(described_class.keys).to eq(%w[verifier identity_lead key_holder board staff contractor patch_lead])
    expect(described_class.fetch("patch_lead")).to have_attributes(scopable: true, scope_source: "knot_programs")
    expect(described_class.fetch("key_holder").requires).to eq(["verifier"])
  end

  it "holds the locked grant rules" do
    rules = described_class.definitions.transform_values { |definition| [definition.grant.rule, definition.revoke.rule] }

    expect(rules).to eq(
      "verifier"      => %w[owner_proposes_board_approves owner_or_identity_lead],
      "identity_lead" => %w[owner_proposes_board_approves owner_proposes_board_approves],
      "key_holder"    => %w[owner_proposes_all_board_approve owner_proposes_all_board_approve],
      "board"         => %w[any_owner any_owner],
      "staff"         => %w[admin admin],
      "contractor"    => %w[admin admin],
      "patch_lead"    => %w[owner_proposes_board_approves owner]
    )
    expect(described_class.fetch("verifier").grant.preconditions_at_approval).to eq(%w[verified_by_another adult])
    expect(described_class.fetch("verifier").grant.preconditions_at_proposal).to eq([])
    expect(described_class.fetch("identity_lead").grant.preconditions_at_proposal).to eq(%w[verified_by_another])
    expect(described_class.fetch("patch_lead").grant).to have_attributes(preconditions_at_proposal: %w[verified_by_another],
                                                                         preconditions_at_approval: %w[verified_by_another])
  end

  it "validates the file at boot without an error" do
    described_class.reset!

    expect(described_class.validate!).to be(true)
  end

  describe "a bad config raises a clear error" do
    it "refuses an unknown key in a role" do
      raw = changed { |roles| roles["staff"]["grnat"] = { "rule" => "admin" } }

      expect { parse(raw) }.to raise_error(described_class::ConfigError, /role staff: unknown key\(s\) grnat/)
    end

    it "refuses an unknown key in a rule" do
      raw = changed { |roles| roles["staff"]["grant"]["approvers"] = 2 }

      expect { parse(raw) }.to raise_error(described_class::ConfigError, /staff grant: unknown key\(s\) approvers/)
    end

    it "refuses an unknown rule" do
      raw = changed { |roles| roles["board"]["grant"]["rule"] = "anyone" }

      expect { parse(raw) }.to raise_error(described_class::ConfigError, /board grant: unknown rule "anyone"/)
    end

    it "refuses an unknown precondition, and a precondition on a rule that applies at once" do
      unknown = changed { |roles| roles["verifier"]["grant"]["preconditions_at_approval"] = %w[verified_by_another tall] }
      immediate = changed { |roles| roles["staff"]["grant"]["preconditions_at_approval"] = %w[adult] }
      nda = changed { |roles| roles["verifier"]["grant"]["preconditions_at_approval"] = %w[verified_by_another adult nda] }

      expect { parse(unknown) }.to raise_error(described_class::ConfigError, /unknown precondition\(s\) tall/)
      expect { parse(immediate) }.to raise_error(described_class::ConfigError, /preconditions need a proposal rule/)
      expect { parse(nda) }.to raise_error(described_class::ConfigError, /unknown precondition\(s\) nda/)
    end

    it "refuses a missing role that the code needs" do
      raw = changed { |roles| roles.delete("key_holder") }

      expect { parse(raw) }.to raise_error(described_class::ConfigError, /missing role\(s\) key_holder/)
    end

    it "refuses an unknown or circular required role" do
      unknown = changed { |roles| roles["staff"]["requires"] = %w[wizard] }
      circular = changed { |roles| roles["staff"]["requires"] = %w[staff] }

      expect { parse(unknown) }.to raise_error(described_class::ConfigError, /requires unknown role\(s\) wizard/)
      expect { parse(circular) }.to raise_error(described_class::ConfigError, /can't require itself/)
    end

    it "refuses a scopable role with no scope source, and a scope source on a global role" do
      no_source = changed { |roles| roles["patch_lead"].delete("scope_source") }
      global = changed { |roles| roles["staff"]["scope_source"] = "knot_programs" }

      expect { parse(no_source) }.to raise_error(described_class::ConfigError, /scopable role needs scope_source/)
      expect { parse(global) }.to raise_error(described_class::ConfigError, /scope_source is only for a scopable role/)
    end

    it "refuses a bad role key, a missing rule and an unknown top-level key" do
      bad_key = changed { |roles| roles["Staff Member"] = roles["staff"] }
      no_rule = changed { |roles| roles["staff"].delete("revoke") }
      top = file.merge("rules" => {})

      expect { parse(bad_key) }.to raise_error(described_class::ConfigError, /role Staff Member: the key must match/)
      expect { parse(no_rule) }.to raise_error(described_class::ConfigError, /role staff: needs revoke/)
      expect { parse(top) }.to raise_error(described_class::ConfigError, /unknown top-level key\(s\) rules/)
    end

    it "stops the boot check" do
      allow(described_class).to receive(:load_file).and_return(changed { |roles| roles["board"]["grant"]["rule"] = "anyone" })
      described_class.reset!

      expect { described_class.validate! }.to raise_error(described_class::ConfigError)
    ensure
      described_class.reset!
    end
  end

  describe "scopes" do
    it "takes the patch lead scopes from the Knot programs, and no scope for a global role" do
      expect(described_class.scopes_for("patch_lead")).to eq(KnotSettings.program_keys)
      expect(described_class.valid_scope?("patch_lead", "ganymede")).to be(true)
      expect(described_class.valid_scope?("patch_lead", "europa")).to be(false)
      expect(described_class.valid_scope?("patch_lead", nil)).to be(false)
      expect(described_class.valid_scope?("staff", nil)).to be(true)
      expect(described_class.valid_scope?("staff", "ganymede")).to be(false)
    end
  end

  describe ".sync!" do
    it "creates one row for each role, and is idempotent" do
      described_class.sync!
      described_class.sync!

      expect(Role.order(:id).pluck(:key)).to eq(described_class.keys)
      expect(Role.find_by!(key: "patch_lead")).to have_attributes(name: "Patch lead", scopable: true, system: true)
    end

    it "updates a changed name and keeps a row the config no longer has" do
      Role.create!(key: "old_role", name: "Old")
      Role.find_or_initialize_by(key: "staff").update!(name: "Something else")

      described_class.sync!

      expect(Role.find_by!(key: "staff").name).to eq("Staff")
      expect(Role.exists?(key: "old_role")).to be(true)
    end

    it "creates the rows on demand through Role.fetch!" do
      expect(Role.fetch!("board")).to have_attributes(key: "board", name: "Board member")
      expect { Role.fetch!("wizard") }.to raise_error(ArgumentError, /Unknown role "wizard"/)
    end
  end
end
