#!/usr/bin/env bash
# Makes a private database for screenshots and builds the assets. Prints the
# database name.
#
#   .claude/skills/pr-screenshots/scripts/prepare.sh
#
# The shared dev and test databases belong to other sessions, so the
# screenshots get their own, named after this worktree's folder: two sessions
# never share it. The schema load puts the queue tables in the same database,
# which the test-env server needs.
set -euo pipefail

name=$(basename "$(git rev-parse --show-toplevel)" | tr -c 'a-zA-Z0-9\n' '_' | tr '[:upper:]' '[:lower:]')
db="weave_shots_$name"
export DATABASE_URL="postgres://localhost/$db" RAILS_ENV=test

# A server from an earlier run holds a connection, and the drop fails. Stop it
# first (serve.sh writes tmp/pids/screenshots-<port>.pid).
bin/rails db:drop DISABLE_DATABASE_ENVIRONMENT_CHECK=1 >/dev/null
bin/rails db:create >/dev/null 2>&1
bin/rails db:schema:load >/dev/null
bun run build >/dev/null 2>&1
bin/rails tailwindcss:build >/dev/null 2>&1
echo "$db"
