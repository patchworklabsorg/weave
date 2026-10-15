# frozen_string_literal: true

require "rails_helper"

# Staging runs the production build, so the only visible difference between
# the two is this frame and label. It must show on staging and never on production.
RSpec.describe "Staging badge", type: :request do
  it "is shown on staging" do
    allow(Weave).to receive(:staging?).and_return(true)

    get login_path

    expect(response.body).to include(">Staging</div>")
    expect(response.body).to include("staging-frame")
  end

  it "is not shown otherwise" do
    get login_path

    expect(response.body).not_to include("Staging")
    expect(response.body).not_to include("staging-frame")
  end
end
