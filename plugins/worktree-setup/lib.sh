# Shared helpers. Sourced by bash.

HERDR="${HERDR_BIN_PATH:-herdr}"
PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

agent_command=claude
agent_prompt=
confirm_delete=true
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

# Machine-wide registry of worktree dev server ports, one "<port>\t<path>" per
# line. Repos derive CONDUCTOR_PORT by hashing the worktree path into 400 blocks
# of 10 ports (55100-59099) on their own, so worktrees of different repos can
# land on the same block; they all honor a CONDUCTOR_PORT that's already set.
PORTS_FILE="$HOME/.herdr/ports"

# True when a process other than one running inside $2 listens on a port in
# the block starting at $1. $LISTENERS is "port:pid" lines from lsof.
block_taken() {
  local port pid cwd
  while IFS=: read -r port pid; do
    (( port >= $1 && port < $1 + 10 )) || continue
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
    [[ "$cwd/" == "$2/"* ]] || return 0
  done <<<"$LISTENERS"
  return 1
}

# The first port of worktree $1's block: its registered one, otherwise the
# block the repos would hash it to, otherwise the next block that no other
# worktree holds and nothing else is listening on. Prints nothing for a main
# checkout, which keeps the repo's default port.
worktree_port() {
  local dir="$1" lock="$PORTS_FILE.lock" tries=0 start i port path
  is_linked_worktree "$dir" || return 0
  dir="$(cd "$dir" && pwd -P)" || return 1
  mkdir -p "$(dirname "$PORTS_FILE")"
  until mkdir "$lock" 2>/dev/null; do
    if (( ++tries > 100 )); then rm -rf "$lock"; tries=0; fi # left by a killed run
    sleep 0.1
  done
  touch "$PORTS_FILE"
  # Forget worktrees that are gone.
  while IFS=$'\t' read -r port path; do
    [[ -d "$path" ]] && printf '%s\t%s\n' "$port" "$path"
  done <"$PORTS_FILE" >"$PORTS_FILE.tmp" && mv "$PORTS_FILE.tmp" "$PORTS_FILE"
  port="$(awk -F'\t' -v d="$dir" '$2 == d { print $1; exit }' "$PORTS_FILE")"
  if [[ -z "$port" ]]; then
    LISTENERS="$(lsof -nP -iTCP -sTCP:LISTEN -Fpn 2>/dev/null |
      awk '/^p/ { pid = substr($0, 2) } /^n/ { sub(/.*:/, ""); print $0 ":" pid }' | sort -u)"
    start=$(( $(printf %s "$dir" | cksum | cut -d' ' -f1) % 400 ))
    for (( i = 0; i < 400; i++ )); do
      port=$(( 55100 + (start + i) % 400 * 10 ))
      cut -f1 "$PORTS_FILE" | grep -qx "$port" && continue
      block_taken "$port" "$dir" && continue
      printf '%s\t%s\n' "$port" "$dir" >>"$PORTS_FILE"
      break
    done
    (( i < 400 )) || port=
  fi
  rmdir "$lock"
  printf %s "$port"
}

# The first message for Claude in the worktree $1: .herdr/prompt.local.md from
# the main checkout (untracked, just for you), then .herdr/prompt.md (committed
# with the repo), then agent_prompt from config.sh.
agent_prompt() {
  local f
  for f in "$(main_checkout "$1")/.herdr/prompt.local.md" "$1/.herdr/prompt.md"; do
    [[ -f "$f" ]] && { cat "$f"; return; }
  done
  printf %s "$agent_prompt"
}
