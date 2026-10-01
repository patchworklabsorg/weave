# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::UsersController, type: :controller do
  include ActiveJob::TestHelper

  let(:admin_user) { create(:user, :verified, :admin) }

  before do
    allow(controller).to receive_messages(current_user: admin_user, authenticate_user!: true, require_admin: true, track_user_session: true)
  end

  def update(user, attrs)
    patch :update, params: { id: user.to_param, user: { first_name: user.first_name, **attrs } }
  end

  it "pushes an edited Slack profile field to Slack" do
    user = create(:user, :verified, slack_id: "U810", slack_cost_center: "CC-1")

    expect { update(user, slack_cost_center: "") }.to have_enqueued_job(PushSlackProfileFieldsJob).with(user.id)
  end

  it "does not push when no Slack profile field changed" do
    user = create(:user, :verified, slack_id: "U811")

    expect { update(user, first_name: "Renamed") }.not_to have_enqueued_job(PushSlackProfileFieldsJob)
  end

  it "does not push for an account that is not in Slack" do
    user = create(:user, :verified)

    expect { update(user, slack_cost_center: "CC-2") }.not_to have_enqueued_job(PushSlackProfileFieldsJob)
  end
end
