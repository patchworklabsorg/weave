# frozen_string_literal: true

namespace :patches do
  desc "Create a patch for each program in config/kyc/knot.yml. Safe to run more than once."
  task sync: :environment do
    PaperTrail.request(whodunnit: "patches:sync") do
      Patch.sync_programs!
    end

    Patch.order(:slug).each do |patch|
      puts "#{patch.slug}: #{patch.name}"
    end
  end

  desc "Copy the roles of an OAuth app into a patch (see PatchRoleImport). " \
       "APP=<public id or uid> PATCH=<slug> PREFIX=<prefix> ACTOR=<superadmin email> " \
       "[GROUP_MAP=slug:role_key,...] [APPLY=1]. A dry run unless APPLY=1."
  task import_app_roles: :environment do
    app_param = ENV["APP"].to_s
    application = Doorkeeper::Application.find_by_public_param(app_param) if app_param.present?
    application ||= Doorkeeper::Application.find_by(uid: app_param) if app_param.present?
    group_map = ENV["GROUP_MAP"].to_s.split(",").map(&:strip).compact_blank.to_h do |pair|
      slug, key = pair.split(":", 2)
      abort "GROUP_MAP takes slug:role_key pairs, not #{pair.inspect}." if slug.blank? || key.blank?
      [slug, key]
    end

    result = PatchRoleImport.call(
      application:,
      patch: Patch.find_by(slug: ENV["PATCH"].to_s),
      prefix: ENV["PREFIX"].to_s,
      actor: User.find_for_any_email(ENV["ACTOR"].to_s),
      group_map:,
      apply: ENV["APPLY"] == "1"
    )
    puts result.lines
  rescue PatchRoleImport::Error => error
    abort error.message
  end
end
