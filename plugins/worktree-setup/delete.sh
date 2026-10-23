#!/usr/bin/env bash
# prefix+a: confirm, run the archive script, then delete the focused worktree.
# The work happens in an overlay so you can answer and watch the output.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

dir=""
if [[ -n "${HERDR_PANE_ID:-}" ]]; then
  dir="$("$HERDR" pane get "$HERDR_PANE_ID" | jq -r '.result.pane | .foreground_cwd // .cwd // empty')"
fi
top="$(git -C "${dir:-/}" rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$top" ]] || ! is_linked_worktree "$top"; then
  notify "Delete worktree" "The focused pane isn't in a linked git worktree"
  exit 0
fi

"$HERDR" plugin pane open --plugin "${HERDR_PLUGIN_ID:-rowhome.worktree-setup}" --entrypoint delete \
  --placement overlay \
  --env "WORKTREE_DIR=$top" --env "WORKTREE_WORKSPACE=${HERDR_WORKSPACE_ID:-}" --focus >/dev/null
