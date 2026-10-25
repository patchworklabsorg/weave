#!/usr/bin/env bash
# Uploads PNG screenshots to the `pr-screenshots` branch through the GitHub
# API and prints the base URL for the PR body. No local git: the worktree and
# its branch stay as they are.
#
#   .claude/skills/pr-screenshots/scripts/upload.sh <folder name, e.g. pr-252> <dir with .png files>
#
# The images go in <folder name>/ on the branch. Links use the commit SHA, so
# a later upload does not change them.
set -euo pipefail

folder=${1:?usage: upload.sh <folder name> <png dir>}
dir=${2:?usage: upload.sh <folder name> <png dir>}
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

entries=()
for file in "$dir"/*.png; do
  printf '{"encoding":"base64","content":"%s"}' "$(base64 < "$file" | tr -d '\n')" > "$work/blob.json"
  sha=$(gh api "repos/$repo/git/blobs" --input "$work/blob.json" -q .sha)
  entries+=("{\"path\":\"$folder/$(basename "$file")\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$sha\"}")
done
[[ ${#entries[@]} -gt 0 ]] || { echo "No .png files in $dir" >&2; exit 1; }
tree_entries=$(IFS=,; echo "${entries[*]}")

# Add to the branch when it exists; start it when it does not.
if parent=$(gh api "repos/$repo/git/ref/heads/pr-screenshots" -q .object.sha 2>/dev/null); then
  base_tree=$(gh api "repos/$repo/git/commits/$parent" -q .tree.sha)
  printf '{"base_tree":"%s","tree":[%s]}' "$base_tree" "$tree_entries" > "$work/tree.json"
  parents="[\"$parent\"]"
else
  printf '{"tree":[%s]}' "$tree_entries" > "$work/tree.json"
  parents="[]"
fi
tree=$(gh api "repos/$repo/git/trees" --input "$work/tree.json" -q .sha)
printf '{"message":"chore: screenshots for %s","tree":"%s","parents":%s}' "$folder" "$tree" "$parents" > "$work/commit.json"
commit=$(gh api "repos/$repo/git/commits" --input "$work/commit.json" -q .sha)

if [[ $parents == "[]" ]]; then
  gh api "repos/$repo/git/refs" -f ref=refs/heads/pr-screenshots -f sha="$commit" >/dev/null
else
  gh api -X PATCH "repos/$repo/git/refs/heads/pr-screenshots" -f sha="$commit" >/dev/null
fi

echo "https://raw.githubusercontent.com/$repo/$commit/$folder"
