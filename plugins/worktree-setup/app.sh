#!/usr/bin/env bash
# Runs in a worktree's app pane: the project's Conductor setup script, then its
# run script(s) side by side, offering a restart whenever they stop. Safe to
# rerun: bash <this file>
set -uo pipefail
source "$(dirname "$0")/lib.sh"

dir="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git checkout"; exit 1; }
cd "$dir" || exit 1
scripts="$(conductor_scripts "$dir")"
setup="$(jq -r '.setup // ""' <<<"$scripts")"
shell="${SHELL:-/bin/sh}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

run_setup() {
  [[ -n "$setup" ]] || return 0
  say "\$ $setup"
  "$shell" -c "$setup" && return
  notify "Worktree setup failed" "$(basename "$dir"): see its app pane"
  say "Setup failed. Fix it, then rerun: bash $0"
  exit 1
}

# Starts every run script side by side and waits for them all to stop.
run_app() {
  local cmd pids=() stopped=
  while IFS= read -r cmd; do
    say "\$ $cmd"
    "$shell" -c "$cmd" <&3 &
    pids+=($!)
  done < <(jq -r '.run // [] | .[]' <<<"$scripts")
  (( ${#pids[@]} )) || return 1
  # Ctrl-C stops them all; closing the pane stops them and this script.
  trap 'stopped=1; kill "${pids[@]}" 2>/dev/null' INT
  trap 'kill "${pids[@]}" 2>/dev/null; exit' TERM
  wait "${pids[@]}"
  # A trapped Ctrl-C ends the first wait early; let them finish shutting down.
  wait "${pids[@]}" 2>/dev/null
  trap - INT TERM
  [[ -n "$stopped" ]] ||
    notify "App stopped" "$(basename "$dir"): press r in its app tab to restart"
}

# Background jobs get /dev/null as stdin, and watchers like `tailwindcss --watch`
# exit on EOF (taking foreman's whole Procfile down), so hand them the pane's.
exec 3<&0

run_setup
# direnv trusts by path, so a fresh worktree's .envrc/.env (often a symlink the
# setup script just made) starts out blocked.
if command -v direnv >/dev/null && [[ -e .envrc || -e .env ]]; then
  direnv allow "$dir"
fi

# When the app stops (crash or Ctrl-C), r restarts it, s reruns setup first.
while run_app; do
  say "App stopped. [r] restart  [s] setup + restart  [q] quit"
  while IFS= read -rsn1 key; do
    case "$key" in
      r|"") break ;;
      s) run_setup; break ;;
      q) exit 0 ;;
    esac
  done || exit 0
done
