#!/usr/bin/env bash
# Open a reviewr pane below the first agent of every tab that has no reviewr
# pane yet. Tabs whose agent isn't in a git repo are skipped (reviewr needs one).
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-reviewr-below}"

mkdir -p "$STATE_DIR"
LOCK="$STATE_DIR/lock"
# One run at a time, so a burst of agent detections can't open duplicates.
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

panes="$("$HERDR" pane list 2>/dev/null)" || exit 0

while IFS=$'\t' read -r pane dir; do
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  "$HERDR" plugin pane open --plugin persiyanov.reviewr --entrypoint pane \
    --placement split --direction down --target-pane "$pane" --cwd "$dir" --no-focus >/dev/null
done < <(jq -r '
  .result.panes
  | group_by(.tab_id)[]
  | select(all(.[]; .label != "reviewr"))
  | map(select(.agent != null)) | first // empty
  | [.pane_id, (.foreground_cwd // .cwd)] | @tsv' <<<"$panes")
