#!/usr/bin/env bash
# The prefix+a overlay: confirm, run the project's Conductor archive script in
# the worktree, then have herdr delete it. The branch itself is kept.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

dir="${WORKTREE_DIR:?}"
workspace="${WORKTREE_WORKSPACE:?}"
name="$(basename "$dir")"
branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
archive="$(conductor_scripts "$dir" | jq -r '.archive // ""')"

finish() { printf '\n%s\nPress any key to close.' "$1"; read -rsn1; exit 0; }

printf '\033[1mDelete worktree %s\033[0m (branch %s, which is kept)\n%s\n\n' "$name" "$branch" "$dir"
if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
  git -C "$dir" status --short | head -20
  finish "It has uncommitted changes. Commit or discard them first."
fi
if [[ -n "$archive" ]]; then
  echo "Archive script: $archive"
else
  echo "No archive script."
fi
printf '\nDelete it? [y/N] '
read -rsn1 answer
echo
[[ "$answer" == [yY] ]] || exit 0

if [[ -n "$archive" ]]; then
  printf '\n\033[1m$ %s\033[0m\n' "$archive"
  if ! (cd "$dir" && "${SHELL:-/bin/sh}" -c "$archive"); then
    finish "The archive script failed, so the worktree wasn't deleted."
  fi
fi

out="$("$HERDR" worktree remove --workspace "$workspace" 2>&1)" ||
  finish "herdr couldn't delete it: $(jq -r '.error.message // empty' <<<"$out" 2>/dev/null || echo "$out")"
