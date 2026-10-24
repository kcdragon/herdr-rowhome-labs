#!/usr/bin/env bash
# A new worktree: bring its branch up to origin's default branch, start Claude
# in the first tab, open reviewr in a second, and run the project's setup and
# run scripts in an "app" tab.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

dir="$(jq -r '.data.worktree.path // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")"
pane="${HERDR_PANE_ID:-}"
[[ -d "$dir" && -n "$pane" ]] || exit 0

# Herdr branches from the main checkout's HEAD, which is often behind origin.
# Only fast-forwards, so it can't lose anything.
GIT_TERMINAL_PROMPT=0 git -C "$dir" fetch --quiet origin 2>/dev/null
base="$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
if [[ -n "$base" && -z "$(git -C "$dir" status --porcelain)" ]] &&
  git -C "$dir" merge-base --is-ancestor HEAD "$base"; then
  git -C "$dir" merge --quiet --ff-only "$base"
fi

# Reviewr gets a tab of its own.
out="$("$HERDR" plugin pane open --plugin persiyanov.reviewr --entrypoint pane --placement tab \
  --workspace "${HERDR_WORKSPACE_ID:-}" --cwd "$dir" --no-focus 2>&1)"
review_tab="$(jq -r '.result.plugin_pane.pane.tab_id // empty' <<<"$out" 2>/dev/null)"
[[ -n "$review_tab" ]] && "$HERDR" tab rename "$review_tab" reviewr >/dev/null

scripts="$(conductor_scripts "$dir")"
if [[ -n "$(jq -r '(.setup // "") + (.run // [] | join(""))' <<<"$scripts")" ]]; then
  out="$("$HERDR" tab create --workspace "${HERDR_WORKSPACE_ID:-}" --cwd "$dir" --label app --no-focus 2>&1)"
  app="$(jq -r '.result.root_pane.pane_id // empty' <<<"$out" 2>/dev/null)"
  if [[ -n "$app" ]]; then
    "$HERDR" pane run "$app" "bash $(printf %q "$PLUGIN_ROOT/app.sh")" >/dev/null
  else
    notify "Worktree setup" "Couldn't open the app tab in $(basename "$dir"): $out"
  fi
fi

[[ -n "${HERDR_TAB_ID:-}" ]] && "$HERDR" tab rename "$HERDR_TAB_ID" "$agent_command" >/dev/null
"$HERDR" pane run "$pane" "$agent_command" >/dev/null
