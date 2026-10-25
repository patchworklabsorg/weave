#!/usr/bin/env bash
# PreToolUse hook (Bash): block `gh pr create` on a Weave branch that changes
# what people see until the pr-screenshots skill has run on its current UI.
# The skill writes the marker file with the HEAD it screenshotted.
set -euo pipefail

command -v jq >/dev/null || { echo "require-pr-screenshots: jq is missing, so gh pr create is not checked" >&2; exit 0; }

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# Only gate PR creation (`gh pr new` is an alias), with or without a path to gh.
grep -Eq '(^|[;&|(`[:space:]])([^[:space:];&|]*/)?gh[[:space:]]+pr[[:space:]]+(create|new)([[:space:]]|$)' <<<"$cmd" || exit 0

# Follow a leading `cd <dir> &&` or `cd <dir>;`, quoted or not.
if [[ $cmd =~ ^[[:space:]\(]*cd[[:space:]]+\"([^\"]+)\"[[:space:]]*(\&\&|\;) ]] ||
   [[ $cmd =~ ^[[:space:]\(]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*(\&\&|\;) ]]; then
  dir=${BASH_REMATCH[1]}
  dir=${dir/#\~/$HOME}
  [[ $dir == /* ]] || dir="$cwd/$dir"
else
  dir=$cwd
fi

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
# Only repos that carry this skill: other Rails apps have their own rules.
[[ -f $top/.claude/skills/pr-screenshots/SKILL.md ]] || exit 0
common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)

# The branch is --head/-H when given, else the current branch.
branch=""
if [[ $cmd =~ (--head|-H)[[:space:]=]+([^[:space:]]+) ]]; then
  branch=${BASH_REMATCH[2]##*:}
fi
[[ -n $branch ]] || branch=$(git -C "$dir" branch --show-current)
[[ -n $branch ]] || exit 0
head=$(git -C "$dir" rev-parse --verify --quiet "$branch^{commit}" || git -C "$dir" rev-parse HEAD)

deny() {
  jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

base=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
git -C "$dir" rev-parse --verify --quiet "$base" >/dev/null ||
  deny "require-pr-screenshots can't find $base, so it can't tell whether $branch changes views. Run git fetch origin, then gh pr create again."

# What people see: pages, their helpers, styles, scripts, images and copy.
# Mail templates are left out: the skill can't screenshot email.
ui_paths=(app/views app/helpers app/assets app/javascript config/locales public
          ':(exclude)app/views/*_mailer' ':(exclude)app/views/layouts/mailer*')
[[ -n $(git -C "$dir" diff --name-only "$base...$head" -- "${ui_paths[@]}") ]] || exit 0

marker="$common/pr-screenshots/${branch//\//__}"
hint="Run the pr-screenshots skill (.claude/skills/pr-screenshots/SKILL.md), put the screenshots in the PR body, then run gh pr create again. The skill writes $marker. If the user explicitly said to skip screenshots, write \"skipped\" to that file and retry."
[[ -f $marker ]] || deny "Branch $branch changes what people see and has no screenshots yet. $hint"

shot=$(head -n 1 "$marker")
[[ $shot == skipped ]] && exit 0
# Screenshots of an older commit still count when no UI file changed since.
if git -C "$dir" cat-file -e "$shot^{commit}" 2>/dev/null &&
   git -C "$dir" merge-base --is-ancestor "$shot" "$head" &&
   [[ -z $(git -C "$dir" diff --name-only "$shot" "$head" -- "${ui_paths[@]}") ]]; then
  exit 0
fi
deny "The screenshots for $branch are from ${shot:0:12}, and UI files changed after it. $hint"
