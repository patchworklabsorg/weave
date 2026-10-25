#!/usr/bin/env bash
# Starts the app for screenshots. Run it in the background.
#
#   .claude/skills/pr-screenshots/scripts/serve.sh <db> [port]
#
# RAILS_ENV=test, not development: a worktree has no development credentials
# key, so development sign-in fails with "Missing master key". The test env has
# a throwaway Lockbox key. Bullet raises in the test env, so an N+1 query shows
# as a 500 page: treat it as a bug in the change.
#
# The test env does not reload code. Run this again after each edit: it stops
# the server it started before, waits for it to exit, then starts a new one.
set -euo pipefail

db=${1:?usage: serve.sh <db> [port]}
port=${2:-3077}
pidfile="tmp/pids/screenshots-$port.pid"
mkdir -p tmp/pids

if [[ -f $pidfile ]]; then
  pid=$(cat "$pidfile")
  # Only a puma that this script started: a stale pid may belong to anything.
  if ps -p "$pid" -o command= 2>/dev/null | grep -q puma; then
    kill "$pid"
    for _ in $(seq 1 60); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
  fi
  rm -f "$pidfile"
fi
for _ in $(seq 1 30); do
  lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || break
  sleep 0.5
done

# Puma runs the Solid Queue supervisor. Keep config/recurring.yml (Slack sync,
# retention, ...) out of a screenshot server.
export DATABASE_URL="postgres://localhost/$db" RAILS_ENV=test SOLID_QUEUE_SKIP_RECURRING=true
exec bin/rails server -p "$port" -b 127.0.0.1 -P "$pidfile"
