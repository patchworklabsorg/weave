#!/usr/bin/env bash
# Makes a private database for screenshots and builds the assets.
#
#   .claude/skills/pr-screenshots/scripts/prepare.sh weave_shots_<branch>
#
# The shared dev and test databases belong to other sessions, so the
# screenshots get their own. The schema load puts the queue tables in the same
# database, which the test-env server needs.
set -euo pipefail

db=${1:?usage: prepare.sh <database name>}
# The script drops and loads this database, so it takes only a private name.
[[ $db == weave_shots_* ]] || { echo "The database name must start with weave_shots_" >&2; exit 1; }
export DATABASE_URL="postgres://localhost/$db" RAILS_ENV=test

bin/rails db:drop DISABLE_DATABASE_ENVIRONMENT_CHECK=1 >/dev/null 2>&1 || true
bin/rails db:create
bin/rails db:schema:load
bun run build
bin/rails tailwindcss:build
echo "Ready: DATABASE_URL=$DATABASE_URL"
