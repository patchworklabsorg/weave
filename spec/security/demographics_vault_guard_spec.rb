# frozen_string_literal: true

require "rails_helper"

# The demographics vault has no read path for one member's answers (see
# DemographicsVault and docs/KYC.md). These checks fail when code that shows
# or exports member data starts to touch the vault. If one fails, do not add
# an exception here: count the data through DemographicsReport instead.
RSpec.describe "Demographics vault guard" do # rubocop:disable RSpec/DescribeClass
  root = Rails.root

  vault_terms = [
    "DemographicRecord", "DemographicFold", "DemographicDepartedTotal",
    "demographic_record", "demographic_fold", "demographic_departed_total",
    "DemographicsVault::Reader", "DemographicsVault::Envelope", "Envelope.open", ".envelope",
    "self_description", "age_band"
  ]
  field_terms = -> { DemographicsVault.fields.map { |field| field[:key].to_s } }

  # Places that show, serialize or export data about a member.
  member_facing = [
    "app/serializers/**/*.rb",
    "app/views/**/*.jbuilder",
    "app/controllers/api/**/*.rb",
    "app/controllers/oauth/**/*.rb",
    "app/controllers/admin/**/*.rb",
    "app/views/admin/**/*.erb",
    "app/views/users/**/*.erb",
    "app/mailers/**/*.rb",
    "app/views/*_mailer/**/*.erb",
    "app/services/slack_service.rb",
    "app/jobs/**/*.rb",
    "lib/tasks/**/*.rake",
    "config/initializers/console*.rb",
    "config/blazer.yml"
  ]
  # The aggregate-only admin page and the reporting task.
  allowed = %w[
    app/controllers/admin/demographics_controller.rb
    app/views/admin/demographics/show.html.erb
    lib/tasks/demographics.rake
  ]

  files = member_facing.flat_map { |pattern| Dir.glob(root.join(pattern)) }
                       .map { |path| Pathname(path).relative_path_from(root).to_s } - allowed

  it "scans the files that show or export member data" do
    expect(files).to include("app/serializers/user_serializer.rb", "app/views/admin/users/show.html.erb")
  end

  it "keeps the vault out of every serializer, admin page, export and console helper" do
    terms = vault_terms + field_terms.call
    offenders = files.flat_map do |path|
      text = File.read(root.join(path))
      terms.select { |term| text.include?(term) }.map { |term| "#{path} mentions #{term}" }
    end

    expect(offenders).to be_empty
  end

  it "lets the aggregate admin page show only reports" do
    text = allowed.map { |path| File.read(root.join(path)) }.join("\n")

    expect(text).not_to include("DemographicRecord", "DemographicFold", "DemographicDepartedTotal", "Envelope.open",
                                ".envelope")
  end

  it "opens envelopes only in the reporting run" do
    openers = Dir.glob(root.join("{app,lib,config}/**/*.{rb,rake,erb}")).select do |path|
      text = File.read(path)
      text.include?("Reader.new") || text.include?("Reader.from_env") || text.include?("Envelope.open") || text.include?("reader.open")
    end
    openers = openers.map { |path| Pathname(path).relative_path_from(root).to_s }

    expect(openers).to contain_exactly(
      "app/services/demographics_report.rb",
      "app/services/demographics_vault/reader.rb",
      "lib/tasks/demographics.rake"
    )
  end

  it "keeps the vault out of the user's JSON" do
    expect(create(:user).as_json.keys.join(" ")).not_to include("demographic")
    expect(User.reflect_on_all_associations.map(&:name).join(" ")).not_to include("demographic")
  end

  it "keeps no version history of the vault" do
    expect(DemographicRecord.new).not_to respond_to(:versions)
    [DemographicRecord, DemographicFold, DemographicDepartedTotal].each do |model|
      expect(model.new).not_to respond_to(:versions)
      expect(model.filter_attributes).to include("envelope")
    end
  end
end
