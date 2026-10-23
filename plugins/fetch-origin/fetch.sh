#!/usr/bin/env bash
# `git fetch origin` in every agent's repo, at most once per THROTTLE seconds
# per repo (pass --now to skip the throttle). Keeps origin/main current so
# reviewr's branch diff stops showing work that has already merged, and moves
# squash-merged branches onto it (see catch_up).
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

agents="$("$HERDR" agent list 2>/dev/null)" || exit 0
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
done < <(jq -r '.result.agents[] | (.foreground_cwd // .cwd) // empty' <<<"$agents")
# Plugins must not leave processes behind.
wait

# A squash merge never makes the branch's commits part of the default branch,
# so its merge-base (and reviewr's diff) stays put even after a fetch. When a
# branch's files match origin/<default> exactly and nothing is uncommitted,
# everything on it has landed: point the branch at origin/<default>. Files
# already match, so --soft only moves the ref. The old commit is kept under
# refs/fetch-origin/<branch> (undo: git reset --soft refs/fetch-origin/<branch>).
catch_up() {
  local dir="$1" top base branch
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return
  base="$(git -C "$top" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || return
  branch="$(git -C "$top" symbolic-ref --quiet --short HEAD)" || return
  [[ "$branch" == "${base#origin/}" ]] && return
  [[ -z "$(git -C "$top" status --porcelain 2>/dev/null)" ]] || return
  git -C "$top" diff --quiet "$base" HEAD -- 2>/dev/null || return
  # Already on (or behind) the default branch: nothing to move.
  git -C "$top" merge-base --is-ancestor HEAD "$base" && return
  git -C "$top" update-ref "refs/fetch-origin/$branch" HEAD || return
  git -C "$top" reset --quiet --soft "$base" && echo "$top: moved $branch to $base" >&2
}

# Leave agents that are mid-turn alone; they may be committing.
while IFS= read -r dir; do
  catch_up "$dir"
done < <(jq -r '.result.agents[] | select(.agent_status != "working") | (.foreground_cwd // .cwd) // empty' <<<"$agents")
