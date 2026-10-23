# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: verification_events
# Database name: primary
#
#  id              :bigint           not null, primary key
#  data            :jsonb            not null
#  kind            :string           not null
#  created_at      :datetime         not null
#  actor_id        :bigint
#  user_id         :bigint
#  verification_id :bigint           not null
#
# Indexes
#
#  index_verification_events_on_actor_id         (actor_id)
#  index_verification_events_on_kind             (kind)
#  index_verification_events_on_user_id          (user_id)
#  index_verification_events_on_verification_id  (verification_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verification_id => verifications.id)
#
RSpec.describe VerificationEvent do
  let(:verification) { create(:verification) }

  it "records the step, the actor and the member" do
    actor = create(:user, :identity_team)

    event = described_class.record!(verification, :pre_review_started, actor:)

    expect(event).to have_attributes(kind: "pre_review_started", actor:, user_id: verification.user_id)
  end

  it "accepts only known kinds" do
    expect { described_class.record!(verification, :something_else) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "can't change" do
    event = described_class.record!(verification, :submitted)

    expect { event.update!(kind: "decided") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "can't be deleted" do
    event = described_class.record!(verification, :submitted)

    expect { event.destroy }.to raise_error(described_class::ImmutableError)
    expect(described_class.exists?(event.id)).to be(true)
  end

  it "keeps its verification from being deleted" do
    described_class.record!(verification, :submitted)

    expect { verification.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
