#!/usr/bin/env bash
# `git fetch origin` in every agent's repo, at most once per THROTTLE seconds
# per repo (pass --now to skip the throttle). Keeps origin/main current so
# reviewr's branch diff stops showing work that has already merged.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-fetch-origin}"
THROTTLE=120

mkdir -p "$STATE_DIR"
LOCK="$STATE_DIR/lock"

# One run at a time; events arriving meanwhile are covered by the run in progress.
if ! mkdir "$LOCK" 2>/dev/null; then
  # Break a stale lock left by a crashed run.
  [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]] || exit 0
  rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Never stop to ask for credentials; a failed fetch just waits for the next event.
export GIT_TERMINAL_PROMPT=0

now="$(date +%s)"
seen=$'\n'
while IFS= read -r dir; do
  # Worktrees share refs with their main checkout, so fetch each repo once.
  common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
  [[ "$seen" == *$'\n'"$common"$'\n'* ]] && continue
  seen+="$common"$'\n'
  git -C "$dir" remote get-url origin >/dev/null 2>&1 || continue

  stamp="$STATE_DIR/$(tr '/' '_' <<<"$common")"
  if [[ "${1:-}" != --now && -f "$stamp" ]] && (( now - $(cat "$stamp") < THROTTLE )); then
    continue
  fi
  echo "$now" >"$stamp"
  git -C "$dir" fetch --quiet --prune origin 2>&1 | sed "s|^|$common: |" >&2 &
done < <("$HERDR" agent list 2>/dev/null | jq -r '.result.agents[] | (.foreground_cwd // .cwd) // empty')
# Plugins must not leave processes behind.
wait
