#!/usr/bin/env bash
# Open the new-task form for the repo of the focused pane.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"

# The focused pane's directory, falling back to any cwd in the invocation context.
dir=""
if [[ -n "${HERDR_PANE_ID:-}" ]]; then
  dir="$("$HERDR" pane get "$HERDR_PANE_ID" | jq -r '.result.pane | .foreground_cwd // .cwd // empty')"
fi
if [[ -z "$dir" ]]; then
  dir="$(jq -r 'first(.. | objects | (.foreground_cwd // .cwd // empty))' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}" 2>/dev/null)"
fi

# The main checkout, even when the focused pane is in one of its worktrees.
common="$(git -C "${dir:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [[ -z "$common" ]]; then
  "$HERDR" notification show "New task" --body "The focused pane isn't in a git repo" >/dev/null
  exit 0
fi
root="$(git -C "$common/.." rev-parse --show-toplevel 2>/dev/null || dirname "$common")"

"$HERDR" plugin pane open --plugin "${HERDR_PLUGIN_ID:-rowhome.new-task}" --entrypoint form \
  --placement overlay --env "NEW_TASK_ROOT=$root" >/dev/null
