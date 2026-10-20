#!/usr/bin/env bash
# For every task the form queued: create a worktree workspace, run the
# project's setup script in it, then start the agent and send it the prompt.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-new-task}"
QUEUE="$STATE_DIR/queue"

notify() { "$HERDR" notification show "New task" --body "$1" >/dev/null 2>&1; }
error_message() { jq -r '.error.message // empty' <<<"$1" 2>/dev/null || echo "$1"; }

# Prints the shell command that sets up a fresh checkout: .herdr/setup.sh, else
# Conductor's conductor.json scripts.setup. Prints nothing when there is none.
setup_command() {
  local dir="$1"
  if [[ -f "$dir/.herdr/setup.sh" ]]; then
    echo "bash .herdr/setup.sh"
  elif [[ -f "$dir/conductor.json" ]]; then
    jq -r '.scripts.setup // empty' "$dir/conductor.json"
  fi
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
  local root="$1" agent="$2" branch="$3" prompt="$4"
  local base out pane dir setup code name

  # Branch from the remote's default branch when there is one.
  git -C "$root" fetch --quiet origin 2>/dev/null
  base="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo HEAD)"

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

  setup="$(setup_command "$dir")"
  if [[ -n "$setup" ]]; then
    # Run it in the pane so its output stays visible. CONDUCTOR_ROOT_PATH keeps
    # Conductor setup scripts (e.g. copying .env from the main checkout) working.
    "$HERDR" pane run "$pane" "export HERDR_ROOT_PATH=$(printf %q "$root") CONDUCTOR_ROOT_PATH=$(printf %q "$root"); ( $setup ); echo \"__setup_exit=\$?\"" >/dev/null
    out="$("$HERDR" pane wait-output "$pane" --regex '__setup_exit=[0-9]+' --timeout 1800000 2>&1)"
    code="$(jq -r '.result.matched_line // empty' <<<"$out" 2>/dev/null)"
    code="${code##*=}"
    if [[ "$code" != 0 ]]; then
      notify "Setup failed in $branch; agent not started"
      return
    fi
  fi

  name="$(agent_name "$branch")"
  # Retry briefly: the shell may not have reclaimed the foreground from setup yet.
  for _ in 1 2 3 4 5; do
    out="$("$HERDR" agent start "$name" --kind "$agent" --pane "$pane" --timeout 60000 2>&1)" && break
    [[ "$(jq -r '.error.code // empty' <<<"$out" 2>/dev/null)" == agent_not_ready ]] && break
    sleep 1
  done
  case "$(jq -r '.error.code // empty' <<<"$out" 2>/dev/null)" in
    "") ;;
    agent_not_ready)
      # Usually the agent's "trust this folder?" dialog in the new checkout.
      notify "$name is waiting for you to answer its startup dialog; the prompt is sent after"
      if ! "$HERDR" agent wait "$name" --until idle --until done --timeout 600000 >/dev/null 2>&1; then
        notify "$name never became ready; prompt not sent"
        return
      fi
      ;;
    *)
      notify "Couldn't start $agent in $branch: $(error_message "$out")"
      return
      ;;
  esac

  # A freshly started agent can drop the Enter, leaving the prompt typed but
  # unsent. --wait reports that as agent_prompt_stalled; a timeout here just
  # means the agent is still working, which is fine.
  sleep 2
  out="$("$HERDR" agent prompt "$name" "$prompt" --wait --timeout 15000 2>&1)"
  case "$(jq -r '.error.code // empty' <<<"$out" 2>/dev/null)" in
    "" | timeout) ;;
    agent_prompt_stalled) "$HERDR" agent send-keys "$name" enter >/dev/null ;;
    *) notify "Couldn't send the prompt to $name: $(error_message "$out")" ;;
  esac
}

mkdir -p "$QUEUE"
for task in "$QUEUE"/*.json; do
  [[ -e "$task" ]] || continue
  # Claim the task; a concurrent run may already have it.
  mv "$task" "$task.claimed" 2>/dev/null || continue
  (
    launch "$(jq -r .root "$task.claimed")" "$(jq -r .agent "$task.claimed")" \
      "$(jq -r .branch "$task.claimed")" "$(jq -r .prompt "$task.claimed")"
    rm -f "$task.claimed"
  ) &
done
wait
