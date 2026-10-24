#!/usr/bin/env bash
# Runs in a worktree's app pane: the project's Conductor setup script, then its
# run script(s) side by side. Safe to rerun: bash <this file>
set -uo pipefail
source "$(dirname "$0")/lib.sh"

dir="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git checkout"; exit 1; }
cd "$dir" || exit 1
scripts="$(conductor_scripts "$dir")"
setup="$(jq -r '.setup // ""' <<<"$scripts")"
shell="${SHELL:-/bin/sh}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if [[ -n "$setup" ]]; then
  say "\$ $setup"
  if ! "$shell" -c "$setup"; then
    notify "Worktree setup failed" "$(basename "$dir"): see its app pane"
    say "Setup failed. Fix it, then rerun: bash $0"
    exit 1
  fi
fi

# direnv trusts by path, so a fresh worktree's .envrc/.env (often a symlink the
# setup script just made) starts out blocked.
if command -v direnv >/dev/null && [[ -e .envrc || -e .env ]]; then
  direnv allow "$dir"
fi

# Logs scroll the dev server's URL away, so put it in the tab name once it's
# printed: "app localhost:3000".
if [[ -n "${HERDR_PANE_ID:-}" ]]; then
  (
    out="$("$HERDR" pane wait-output "$HERDR_PANE_ID" \
      --regex 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:[0-9]+)?' 2>/dev/null)" || exit 0
    url="$(jq -r '.result.matched_line // ""' <<<"$out" |
      grep -oE '(localhost|127\.0\.0\.1|0\.0\.0\.0)(:[0-9]+)?' | head -1)"
    tab="$("$HERDR" pane get "$HERDR_PANE_ID" | jq -r '.result.pane.tab_id // empty')"
    [[ -n "$url" && -n "$tab" ]] && "$HERDR" tab rename "$tab" "app ${url/0.0.0.0/localhost}" >/dev/null
  ) &
  watcher=$!
fi

pids=()
while IFS= read -r cmd; do
  say "\$ $cmd"
  "$shell" -c "$cmd" &
  pids+=($!)
done < <(jq -r '.run // [] | .[]' <<<"$scripts")
# Ctrl-C stops them all.
trap 'kill "${pids[@]}" ${watcher:-} 2>/dev/null' INT TERM
(( ${#pids[@]} )) && wait "${pids[@]}"
[[ -n "${watcher:-}" ]] && kill "$watcher" 2>/dev/null
