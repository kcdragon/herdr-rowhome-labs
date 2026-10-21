#!/usr/bin/env bash
# Form (an overlay pane): ask for the branch, then queue the task for
# launch.sh. NEW_TASK_ROOT is the repo's main checkout.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-new-task}"

branch_prefix=""
CONFIG="${HERDR_PLUGIN_CONFIG_DIR:-}/config.sh"
[[ -f "$CONFIG" ]] && source "$CONFIG"

root="${NEW_TASK_ROOT:-$PWD}"
printf 'New worktree in %s  (ctrl+c to cancel)\n\n' "$(basename "$root")"

suggested="${branch_prefix}task-$(date +%m%d-%H%M)"
while :; do
  read -r -p "Branch [$suggested]: " branch
  branch="${branch:-$suggested}"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 && break
  echo "Not a valid branch name: $branch"
done

mkdir -p "$STATE_DIR/queue"
task="$STATE_DIR/queue/$(date +%s).$$.json"
jq -n --arg root "$root" --arg branch "$branch" '{root: $root, branch: $branch}' >"$task.tmp" &&
  mv "$task.tmp" "$task"

"$HERDR" plugin action invoke "${HERDR_PLUGIN_ID:-rowhome.new-task}.launch" >/dev/null
