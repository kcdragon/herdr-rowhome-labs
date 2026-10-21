#!/usr/bin/env bash
# For every task the form queued: create a worktree workspace, export
# Conductor's workspace variables in its pane, run the project's setup script
# there, then start the agent for you to prompt.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-new-task}"
QUEUE="$STATE_DIR/queue"
PORTS="$STATE_DIR/ports"
FIRST_PORT=55100

agent=claude
CONFIG="${HERDR_PLUGIN_CONFIG_DIR:-}/config.sh"
[[ -f "$CONFIG" ]] && source "$CONFIG"

notify() { "$HERDR" notification show "New worktree" --body "$1" >/dev/null 2>&1; }
error_message() { jq -r '.error.message // empty' <<<"$1" 2>/dev/null || echo "$1"; }

# Prints the project's setup command, read the way Conductor does: the
# gitignored .conductor/settings.local.toml (from the main checkout), then
# .conductor/settings.toml, then the legacy conductor.json.
setup_command() {
  local root="$1" dir="$2" toml
  for toml in "$root/.conductor/settings.local.toml" "$dir/.conductor/settings.toml"; do
    [[ -f "$toml" ]] || continue
    python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb")).get("scripts", {}).get("setup", ""))' "$toml" 2>/dev/null |
      grep . && return
  done
  [[ -f "$dir/conductor.json" ]] && jq -r '.scripts.setup // empty' "$dir/conductor.json"
}

# Gives each worktree its own block of ten ports, like Conductor's
# CONDUCTOR_PORT..CONDUCTOR_PORT+9. Blocks of deleted worktrees are reused.
allocate_port() {
  local dir="$1" port
  mkdir "$PORTS.lock" 2>/dev/null || { sleep 1; mkdir "$PORTS.lock" 2>/dev/null; }
  touch "$PORTS"
  # Drop worktrees that no longer exist.
  while IFS=$'\t' read -r port path; do
    [[ -d "$path" ]] && printf '%s\t%s\n' "$port" "$path"
  done <"$PORTS" >"$PORTS.tmp" && mv "$PORTS.tmp" "$PORTS"
  port="$(awk -F'\t' -v d="$dir" '$2 == d { print $1 }' "$PORTS")"
  if [[ -z "$port" ]]; then
    port=$FIRST_PORT
    while cut -f1 "$PORTS" | grep -qx "$port"; do port=$((port + 10)); done
    printf '%s\t%s\n' "$port" "$dir" >>"$PORTS"
  fi
  rmdir "$PORTS.lock" 2>/dev/null
  echo "$port"
}

# Agent names must be unique and match [a-z][a-z0-9_-]{0,31}.
agent_name() {
  local base taken name n=2
  base="$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs 'a-z0-9_-' '-' | sed 's/^[^a-z]*//' | cut -c1-28 | sed 's/-*$//')"
  base="${base:-task}"
  taken="$("$HERDR" agent list 2>/dev/null | jq -r '.result.agents[].name // empty')"
  name="$base"
  while grep -qxF "$name" <<<"$taken"; do
    name="$base-$n"
    n=$((n + 1))
  done
  echo "$name"
}

launch() {
  local root="$1" branch="$2"
  local base default_branch out pane dir setup env code

  # Branch from the remote's default branch when there is one.
  git -C "$root" fetch --quiet origin 2>/dev/null
  base="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo HEAD)"
  default_branch="${base#origin/}"
  [[ "$default_branch" == HEAD ]] && default_branch="$(git -C "$root" symbolic-ref --quiet --short HEAD)"

  if ! out="$("$HERDR" worktree create --cwd "$root" --branch "$branch" --base "$base" --label "$branch" --focus 2>&1)"; then
    notify "Couldn't create worktree $branch: $(error_message "$out")"
    return
  fi
  pane="$(jq -r '.result.root_pane.pane_id' <<<"$out")"
  dir="$(jq -r '.result.worktree.path' <<<"$out")"

  # A branch started from origin/main tracks it; let the first push pick the upstream.
  if [[ "$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" == "$base" ]]; then
    git -C "$dir" branch --quiet --unset-upstream
  fi

  # Exported in the pane's shell, so the setup script, the agent and anything
  # you run there later all see them.
  env="export CONDUCTOR_IS_LOCAL=1"
  env+=" CONDUCTOR_WORKSPACE_NAME=$(printf %q "$(basename "$dir")")"
  env+=" CONDUCTOR_WORKSPACE_PATH=$(printf %q "$dir")"
  env+=" CONDUCTOR_ROOT_PATH=$(printf %q "$root")"
  env+=" CONDUCTOR_DEFAULT_BRANCH=$(printf %q "$default_branch")"
  env+=" CONDUCTOR_PORT=$(allocate_port "$dir")"

  setup="$(setup_command "$root" "$dir")"
  if [[ -z "$setup" ]]; then
    "$HERDR" pane run "$pane" "$env; clear" >/dev/null
  else
    # Run it in the pane so its output stays visible.
    "$HERDR" pane run "$pane" "$env; ( $setup ); echo \"__setup_exit=\$?\"" >/dev/null
    out="$("$HERDR" pane wait-output "$pane" --regex '__setup_exit=[0-9]+' --timeout 1800000 2>&1)"
    code="$(jq -r '.result.matched_line // empty' <<<"$out" 2>/dev/null)"
    code="${code##*=}"
    if [[ "$code" != 0 ]]; then
      notify "Setup failed in $branch; $agent not started"
      return
    fi
  fi

  # Retry briefly: the shell may not have reclaimed the foreground yet. A
  # blocked start (e.g. a "trust this folder?" dialog) is fine: you answer it.
  for _ in 1 2 3 4 5; do
    out="$("$HERDR" agent start "$(agent_name "$branch")" --kind "$agent" --pane "$pane" --timeout 60000 2>&1)" && return
    [[ "$(jq -r '.error.code // empty' <<<"$out" 2>/dev/null)" == agent_not_ready ]] && return
    sleep 1
  done
  notify "Couldn't start $agent in $branch: $(error_message "$out")"
}

mkdir -p "$QUEUE"
for task in "$QUEUE"/*.json; do
  [[ -e "$task" ]] || continue
  # Claim the task; a concurrent run may already have it.
  mv "$task" "$task.claimed" 2>/dev/null || continue
  (
    launch "$(jq -r .root "$task.claimed")" "$(jq -r .branch "$task.claimed")"
    rm -f "$task.claimed"
  ) &
done
wait
