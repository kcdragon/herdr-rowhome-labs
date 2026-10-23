# Shared helpers. Sourced by bash.

HERDR="${HERDR_BIN_PATH:-herdr}"
PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

agent_command=claude
CONFIG="${HERDR_PLUGIN_CONFIG_DIR:-}/config.sh"
[[ -f "$CONFIG" ]] && source "$CONFIG"

notify() { "$HERDR" notification show "$1" --body "$2" >/dev/null 2>&1; }

# The main checkout of the repo $1 belongs to.
main_checkout() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  git -C "$common/.." rev-parse --show-toplevel 2>/dev/null || dirname "$common"
}

# True when $1 is a linked worktree rather than a main checkout.
is_linked_worktree() {
  [[ "$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)" != \
     "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]]
}

# JSON of the worktree $1's Conductor scripts (see scripts.py).
conductor_scripts() {
  python3 "$PLUGIN_ROOT/scripts.py" "$(main_checkout "$1")" "$1" 2>/dev/null || echo '{}'
}
