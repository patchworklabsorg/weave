# frozen_string_literal: true

require "rails_helper"

# Thread Count is strictly internal (proposal v0.8, section 05): never in a
# member-facing view, an OAuth claim, the directory API, a webhook or a
# serializer. This spec fails when code outside the staff tools starts to use
# it. Add a file to `allowed` only for staff tooling, never for anything a
# member or an app can read.
RSpec.describe "Thread Count stays internal" do # rubocop:disable RSpec/DescribeClass
  allowed = [
    /\Aapp\/services\/thread_count(\.rb|\/)/,
    /\Aapp\/models\/thread_count\//,
    /\Aapp\/controllers\/admin\/user_thread_count(s|_entries)_controller\.rb\z/,
    /\Aapp\/views\/admin\//,
    /\Aapp\/helpers\/thread_count_helper\.rb\z/,
    # Write only: a service reports a project outcome and gets a receipt.
    /\Aapp\/controllers\/api\/v1\/project_events_controller\.rb\z/,
    /\Aapp\/serializers\/thread_count_project_event_serializer\.rb\z/,
    # The data-category registry names the ledger only so that deletion
    # destroys it. Takeout never exports it.
    /\Aapp\/services\/data_categories\.rb\z/
  ].freeze
  pattern = /ThreadCount|thread_count|Thread Count/

  it "is used only by the staff tools and the write-only project event API" do
    roots = %w[app lib config/initializers]
    files = roots.flat_map { |root| Dir[Rails.root.join(root, "**/*").to_s] }.select { |path| File.file?(path) }
    offenders = files.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
                     .reject { |path| path.start_with?("app/assets/builds/") }
                     .reject { |path| allowed.any? { |rule| rule.match?(path) } }
                     .select { |path| File.binread(Rails.root.join(path)).force_encoding(Encoding::UTF_8).scrub.match?(pattern) }

    expect(offenders).to be_empty, "Thread Count is used outside the staff tools: #{offenders.join(', ')}"
  end

  it "has no column on users, so a serializer can't pick it up by accident" do
    expect(User.column_names.grep(/thread|trust|score/)).to be_empty
  end

  describe "with entries on file" do
    let(:member) { create(:user, :verified) }
    let(:application) { Doorkeeper::Application.create!(name: "App", redirect_uri: "https://app.example.com/cb", scopes: "openid directory") }

    before do
      create(:thread_count_entry, user: member, kind: "board_vouch", level: nil, reason: "SECRET-REASON")
    end

    def leak?(json)
      text = json.to_json
      text.match?(/thread|trust|score|weight|vouch/i) || text.include?("SECRET-REASON")
    end

    it "is not in the user serializer" do
      expect(leak?(UserSerializer.new(member, include_addresses: true).as_json)).to be(false)
    end

    it "is not in the directory API serializer" do
      expect(leak?(DirectoryUserSerializer.new(member, application).as_json)).to be(false)
    end

    it "is not in the project event receipt beyond what the service sent" do
      service = create(:service)
      result = ThreadCount::Ledger.record_project_event(subject: member, service:, outcome: "approved", project_ref: "p-1")

      expect(ThreadCountProjectEventSerializer.new(result.entry).as_json.keys).to contain_exactly(:id, :project_ref, :kind, :created_at)
    end

    it "is not in the member's own profile page", type: :request do
      sign_in_via_magic_link(member)

      get profile_path

      expect(response.body).not_to match(/Thread Count|SECRET-REASON/)
    end
  end
end
