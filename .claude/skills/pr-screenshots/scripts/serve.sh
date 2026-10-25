#!/usr/bin/env bash
# Starts the app for screenshots. Run it in the background.
#
#   .claude/skills/pr-screenshots/scripts/serve.sh weave_shots_<branch> [port]
#
# RAILS_ENV=test, not development: a worktree has no development credentials
# key, so development sign-in fails with "Missing master key". The test env has
# a throwaway Lockbox key. Bullet raises in the test env, so an N+1 query shows
# as a 500 page: treat it as a bug in the change.
#
# The test env does not reload code. Restart the server after each edit.
set -euo pipefail

db=${1:?usage: serve.sh <database name> [port]}
port=${2:-3077}
pidfile="tmp/pids/screenshots-$port.pid"
mkdir -p tmp/pids
[[ -f $pidfile ]] && kill "$(cat "$pidfile")" 2>/dev/null || true

export DATABASE_URL="postgres://localhost/$db" RAILS_ENV=test
exec bin/rails server -p "$port" -b 127.0.0.1 -P "$pidfile"
