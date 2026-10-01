# frozen_string_literal: true

require "rails_helper"

# Staging runs the production build, so the only visible difference between
# the two is this marker. It must show on staging and never on production.
RSpec.describe "Staging badge", type: :request do
  it "is shown on staging" do
    allow(Weave).to receive(:staging?).and_return(true)

    get login_path

    expect(response.body).to include(">\n    Staging\n  </div>")
  end

  it "is not shown otherwise" do
    get login_path

    expect(response.body).not_to include("Staging")
  end
end
