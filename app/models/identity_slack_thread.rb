# frozen_string_literal: true

# == Schema Information
#
# Table name: identity_slack_threads
# Database name: primary
#
#  id         :bigint           not null, primary key
#  channel    :string           not null
#  ts         :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_identity_slack_threads_on_user_id_and_channel  (user_id,channel) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# The Slack thread that holds every identity team notice about one member,
# in one channel (NotifyIdentityTeamJob). The first notice about the member
# is the parent message; the next ones are replies, so the channel shows one
# line per member. ts is the parent message's Slack timestamp.
class IdentitySlackThread < ApplicationRecord
  belongs_to :user

  validates :channel, presence: true

  # The thread row for the member in the channel, made once. Two jobs at the
  # same time get the same row (unique index on user_id + channel).
  def self.for(user, channel) = create_or_find_by!(user:, channel:)

end
