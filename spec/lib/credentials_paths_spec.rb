# frozen_string_literal: true

require "rails_helper"
require "fileutils"
require "tmpdir"

RSpec.describe CredentialsPaths do
  let(:root) do
    Pathname.new(Dir.mktmpdir).tap { |dir| dir.join("config/credentials").mkpath }
  end

  after { FileUtils.remove_entry(root) if root.exist? }

  def resolve(env) = described_class.resolve(root: root, env: env)

  context "when the environment has its own credentials file" do
    before { root.join("config/credentials/development.yml.enc").write("x") }

    it "pairs it with that environment's key" do
      content, key = resolve("development")

      expect(content).to eq(root.join("config/credentials/development.yml.enc"))
      expect(key).to eq(root.join("config/credentials/development.key"))
    end

    # The regression this module exists for: Rails resolves the two paths
    # independently, so an absent per-environment key falls back to master.key
    # and gets handed a file it cannot decrypt, aborting boot.
    it "does not fall back to master.key when that key is missing" do
      root.join("config/master.key").write("x")

      _content, key = resolve("development")

      expect(key).to eq(root.join("config/credentials/development.key"))
      expect(key.exist?).to be(false)
    end
  end

  context "when the environment has no credentials file of its own" do
    before { root.join("config/credentials.yml.enc").write("x") }

    it "falls back to the shared file and master.key" do
      content, key = resolve("test")

      expect(content).to eq(root.join("config/credentials.yml.enc"))
      expect(key).to eq(root.join("config/master.key"))
    end
  end

  it "never mixes one environment's file with another's key" do
    root.join("config/credentials/production.yml.enc").write("x")

    content, key = resolve("production")

    expect(content.dirname).to eq(key.dirname)
  end
end
