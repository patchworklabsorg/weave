# frozen_string_literal: true

# The append-only log of key custody (see KeyCustody): ceremonies, hardware
# keys, recovery, compromise and rotation. A row never holds a share, a
# PRF output or a key: only ids, counts and reasons.
# == Schema Information
#
# Table name: key_custody_events
# Database name: primary
#
#  id         :bigint           not null, primary key
#  data       :jsonb            not null
#  kind       :string           not null
#  created_at :datetime         not null
#  actor_id   :bigint
#  key_set_id :bigint
#  subject_id :bigint
#
# Indexes
#
#  index_key_custody_events_on_actor_id    (actor_id)
#  index_key_custody_events_on_created_at  (created_at)
#  index_key_custody_events_on_key_set_id  (key_set_id)
#  index_key_custody_events_on_subject_id  (subject_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (key_set_id => key_custody_key_sets.id)
#  fk_rails_...  (subject_id => users.id) ON DELETE => nullify
#
class KeyCustodyEvent < ApplicationRecord
  KINDS = %w[
    ceremony_started ceremony_completed key_set_activated key_set_compromised key_set_retired key_set_discarded
    hardware_key_enrolled seal_key_registered hardware_key_revoked share_rewrapped
    rotation_completed data_keys_rewrapped unlock_failed share_given
  ].freeze

  # The board gets an email for these kinds. A hardware key revoke and the
  # discard of a pending key set are one-person actions, so the board hears
  # about each one.
  BOARD_KINDS = %w[ceremony_completed key_set_activated key_set_compromised key_set_discarded hardware_key_enrolled
                   hardware_key_revoked share_rewrapped rotation_completed unlock_failed].freeze

  class ImmutableError < StandardError; end

  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, class_name: "User", optional: true
  belongs_to :key_set, class_name: "KeyCustodyKeySet", optional: true

  validates :kind, inclusion: { in: KINDS }

  before_update { raise ImmutableError, "Key custody events can't change" }
  before_destroy { raise ImmutableError, "Key custody events can't be deleted" }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.record!(kind, actor: nil, subject: nil, key_set: nil, **data)
    create!(kind: kind.to_s, actor:, subject:, key_set:, data:)
  end

  def readonly? = persisted? || super

  def board_kind? = BOARD_KINDS.include?(kind)

  # One line for the key custody page, the email and the board report.
  def summary
    who = actor&.full_name || (actor_id ? "A deleted user" : "Weave")
    about = subject&.full_name || "a deleted user"
    set = key_set ? "key set #{key_set.public_id}" : "a key set"
    case kind
    when "ceremony_started" then "#{who} started a key ceremony."
    when "ceremony_completed" then "#{who} completed a key ceremony: #{set}, #{data['share_count']} shares, any #{data['threshold']} unlock."
    when "key_set_activated" then "#{set.capitalize} is active."
    when "key_set_compromised" then "#{set.capitalize} is marked compromised (#{data['reason'].to_s.humanize.downcase}). Rotate it."
    when "key_set_retired" then "#{set.capitalize} is retired. Its shares are useless."
    when "key_set_discarded" then "#{who} discarded the pending #{set}: #{data['reason']}. Its shares are useless."
    when "hardware_key_enrolled" then "#{who} enrolled a #{data['role']} hardware key for #{about}."
    when "seal_key_registered" then "#{about} set up the seal key of a hardware key on their own computer."
    when "hardware_key_revoked" then "#{who} revoked a #{data['role']} hardware key of #{about}: #{data['reason']}."
    when "share_rewrapped" then "#{about} wrapped their share for a new hardware key."
    when "rotation_completed" then "#{set.capitalize} replaced #{data['old_key_set_id']}: #{data['rewrapped']} sealed images re-wrapped."
    when "data_keys_rewrapped" then "#{data['rewrapped']} sealed images re-wrapped to #{set}."
    when "unlock_failed" then "An unlock of #{set} failed: #{data['reason']}."
    when "share_given" then "#{who} gave their #{data['share'] == 'old' ? 'old' : 'new'} share for the activation of #{set}" \
                            "#{' (in the ceremony)' if data['via'] == 'ceremony'}."
    else kind.humanize
    end
  end

end
