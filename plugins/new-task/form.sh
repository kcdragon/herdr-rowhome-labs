#!/usr/bin/env bash
# Popup form: ask for the agent, prompt and branch, then queue the task for
# launch.sh. NEW_TASK_ROOT is the repo's main checkout.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-new-task}"

agent=claude
branch_prefix=""
CONFIG="${HERDR_PLUGIN_CONFIG_DIR:-}/config.sh"
[[ -f "$CONFIG" ]] && source "$CONFIG"

root="${NEW_TASK_ROOT:-$PWD}"
printf 'New task in %s  (ctrl+c to cancel)\n\n' "$(basename "$root")"

read -r -p "Agent [$agent]: " answer
agent="${answer:-$agent}"

read -r -e -p "Prompt (empty opens \$EDITOR): " prompt
if [[ -z "$prompt" ]]; then
  file="$(mktemp)"
  "${EDITOR:-vi}" "$file"
  prompt="$(cat "$file")"
  rm -f "$file"
fi
if [[ -z "${prompt//[[:space:]]/}" ]]; then
  echo "No prompt; cancelled."
  sleep 1
  exit 0
fi

# Suggest a branch from the first few words of the prompt.
slug="$(tr '[:upper:]' '[:lower:]' <<<"$prompt" | tr -cs 'a-z0-9' '-' | cut -d- -f1-5 | cut -c1-40 | sed 's/^-*//; s/-*$//')"
while :; do
  read -r -p "Branch [$branch_prefix$slug]: " branch
  branch="${branch:-$branch_prefix$slug}"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 && break
  echo "Not a valid branch name: $branch"
done

mkdir -p "$STATE_DIR/queue"
task="$STATE_DIR/queue/$(date +%s).$$.json"
jq -n --arg root "$root" --arg agent "$agent" --arg branch "$branch" --arg prompt "$prompt" \
  '{root: $root, agent: $agent, branch: $branch, prompt: $prompt}' >"$task.tmp" && mv "$task.tmp" "$task"

"$HERDR" plugin action invoke "${HERDR_PLUGIN_ID:-rowhome.new-task}.launch" >/dev/null
