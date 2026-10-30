#!/usr/bin/env bash
# herdr's terminal.default_shell: every pane starts here. In a linked worktree,
# export the worktree's registered CONDUCTOR_PORT (see worktree_port in lib.sh)
# so everything run in the pane uses it, then become the user's shell. Any
# failure still ends in the shell, so a bug here can't break panes.
shell="${SHELL:-/bin/zsh}"
[[ "$shell" == "${BASH_SOURCE[0]}" || ! -x "$shell" ]] && shell=/bin/zsh

if [[ -z "${CONDUCTOR_PORT:-}" ]] && source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/lib.sh" 2>/dev/null; then
  top="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$top" ]] && port="$(worktree_port "$top" 2>/dev/null)"
  [[ -n "${port:-}" ]] && export CONDUCTOR_PORT="$port"
fi

# A command (e.g. herdr starting an agent) runs as given; otherwise start a
# login shell, as herdr does by default.
(( $# )) && exec "$shell" "$@"
exec -a "-$(basename "$shell")" "$shell"
