#!/usr/bin/env bash
# PreToolUse hook (Bash): block `gh pr create` on a branch that changes what
# people see until the pr-screenshots skill has run on it. The skill writes
# the marker file. Branches that change no views, helpers, CSS or JS pass.
set -euo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# Only gate PR creation.
grep -Eq '(^|[;&|(`[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' <<<"$cmd" || exit 0

# Follow a leading `cd <dir> &&`.
if [[ $cmd =~ ^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*\&\& ]]; then
  dir=${BASH_REMATCH[1]}
  dir=${dir/#\~/$HOME}
  [[ $dir == /* ]] || dir="$cwd/$dir"
else
  dir=$cwd
fi

common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[[ -n $branch ]] || exit 0

# Only this repo's UI paths count.
base=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
ui_changes=$(git -C "$dir" diff --name-only "$base...HEAD" -- app/views app/helpers app/assets/tailwind app/javascript 2>/dev/null || true)
[[ -n $ui_changes ]] || exit 0

marker="$common/pr-screenshots/${branch//\//__}"
[[ -f $marker ]] && exit 0

jq -n --arg branch "$branch" --arg marker "$marker" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Branch \($branch) changes views, helpers, CSS or JS, and has no screenshots yet. Run the pr-screenshots skill (.claude/skills/pr-screenshots/SKILL.md), put the screenshots in the PR body, then run gh pr create again. The skill writes \($marker) when it finishes. If the user explicitly said to skip screenshots, write that file with the content \"skipped\" and retry.")
  }
}'
