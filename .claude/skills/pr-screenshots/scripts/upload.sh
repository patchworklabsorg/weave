#!/usr/bin/env bash
# Uploads screenshots to the `pr-screenshots` branch through the GitHub API
# and prints the base URL for the PR body. No local git: the worktree and its
# branch stay as they are.
#
#   .claude/skills/pr-screenshots/scripts/upload.sh <folder name, e.g. pr-252> <shots dir>
#
# The repo is public and the links use a commit SHA, so an upload is public
# and permanent: deleting the branch later does not take the images back.
# Only files named <name>-<light|dark>-<width>.png are uploaded, so other
# screenshots in the folder stay local. The script lists them before it sends.
set -euo pipefail
shopt -s nullglob

folder=${1:?usage: upload.sh <folder name> <shots dir>}
dir=${2:?usage: upload.sh <folder name> <shots dir>}
[[ $folder =~ ^[A-Za-z0-9._-]+$ ]] || { echo "The folder name may use letters, digits, . _ and - only" >&2; exit 1; }
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

files=()
for file in "$dir"/*-light-*.png "$dir"/*-dark-*.png; do
  [[ $(basename "$file") =~ ^[A-Za-z0-9._-]+-(light|dark)-[0-9]+\.png$ && -s $file ]] && files+=("$file")
done
[[ ${#files[@]} -gt 0 ]] || { echo "No <name>-<light|dark>-<width>.png files in $dir" >&2; exit 1; }
echo "Uploading ${#files[@]} files to $repo, branch pr-screenshots, folder $folder:" >&2
printf '  %s\n' "${files[@]##*/}" >&2

entries="[]"
for file in "${files[@]}"; do
  base64 < "$file" | tr -d '\n' > "$work/b64"
  jq -Rs '{encoding: "base64", content: .}' "$work/b64" > "$work/blob.json"
  sha=$(gh api "repos/$repo/git/blobs" --input "$work/blob.json" -q .sha)
  entries=$(jq -c --arg path "$folder/$(basename "$file")" --arg sha "$sha" \
    '. + [{path: $path, mode: "100644", type: "blob", sha: $sha}]' <<<"$entries")
done

# Add to the branch when it exists; start it when it does not. Another
# upload can move the branch between the read and the write, so try again.
for attempt in 1 2 3; do
  if parent=$(gh api "repos/$repo/git/ref/heads/pr-screenshots" -q .object.sha 2>/dev/null); then
    base_tree=$(gh api "repos/$repo/git/commits/$parent" -q .tree.sha)
    jq -n --arg base "$base_tree" --argjson tree "$entries" '{base_tree: $base, tree: $tree}' > "$work/tree.json"
    parents=$(jq -nc --arg p "$parent" '[$p]')
  else
    jq -n --argjson tree "$entries" '{tree: $tree}' > "$work/tree.json"
    parents="[]"
  fi
  tree=$(gh api "repos/$repo/git/trees" --input "$work/tree.json" -q .sha)
  jq -n --arg msg "chore: screenshots for $folder" --arg tree "$tree" --argjson parents "$parents" \
    '{message: $msg, tree: $tree, parents: $parents}' > "$work/commit.json"
  commit=$(gh api "repos/$repo/git/commits" --input "$work/commit.json" -q .sha)

  if [[ $parents == "[]" ]]; then
    gh api "repos/$repo/git/refs" -f ref=refs/heads/pr-screenshots -f sha="$commit" >/dev/null 2>&1 && break
  else
    gh api -X PATCH "repos/$repo/git/refs/heads/pr-screenshots" -f sha="$commit" >/dev/null 2>&1 && break
  fi
  [[ $attempt -lt 3 ]] || { echo "The pr-screenshots branch kept moving. Run the upload again." >&2; exit 1; }
done

echo "https://raw.githubusercontent.com/$repo/$commit/$folder"
