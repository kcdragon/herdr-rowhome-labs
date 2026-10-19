#!/usr/bin/env bash
# Look up the GitHub PR for every agent pane's current branch and report it as
# pane metadata tokens: $pr, $pr_state, $pr_checks, $pr_review.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
SOURCE="plugin:${HERDR_PLUGIN_ID:-rowhome.github-pr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-github-pr}"
TOKENS=(pr pr_state pr_checks pr_review pr_url)

mkdir -p "$STATE_DIR"
LOCK="$STATE_DIR/lock"
DIRTY="$STATE_DIR/dirty"

# Events can fire in bursts. Only one refresh runs at a time; anyone arriving
# while it runs marks it dirty so it loops once more instead of piling up.
if ! mkdir "$LOCK" 2>/dev/null; then
  # Break a stale lock left by a crashed run.
  if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]]; then
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    touch "$DIRTY"
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

clear_pane() {
  local args=()
  for t in "${TOKENS[@]}"; do args+=(--clear-token "$t"); done
  "$HERDR" pane report-metadata "$1" --source "$SOURCE" "${args[@]}" >/dev/null
}

# Prints "pr state checks review url" (0x1f-separated) for the PR of the branch checked out
# in $1, or nothing when there is no PR.
lookup_pr() {
  local dir="$1" branch
  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" || return 0
  case "$branch" in main|master|develop|trunk) return 0 ;; esac

  (cd "$dir" && gh pr view --json number,state,isDraft,reviewDecision,statusCheckRollup,url 2>/dev/null) |
    jq -r '
      def checks:
        [.statusCheckRollup[]? | (.conclusion // .state // "") | ascii_upcase] as $c
        | if ($c | length) == 0 then ""
          elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED") then "✗ checks"
          elif any($c[]; . == "" or . == "PENDING" or . == "QUEUED" or . == "IN_PROGRESS" or . == "EXPECTED") then "● checks"
          else "✓ checks" end;
      def review:
        { "APPROVED": "approved", "CHANGES_REQUESTED": "changes", "REVIEW_REQUIRED": "in review" }[.reviewDecision // ""] // "";
      def state:
        if .state == "OPEN" and .isDraft then "draft" else (.state | ascii_downcase) end;
      [ "#\(.number)", state, (if .state == "OPEN" then checks else "" end),
        (if .state == "OPEN" then review else "" end), .url ] | join("\u001f")'
}

refresh_all() {
  local agents
  agents="$("$HERDR" agent list 2>/dev/null)" || return 0

  # One gh call per directory, shared by every pane in it.
  declare -A cache=()
  local pane dir key result
  while IFS=$'\t' read -r pane dir; do
    [[ -z "$pane" ]] && continue
    key="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)@$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [[ -z "${cache[$key]+x}" ]]; then
      cache[$key]="$(lookup_pr "$dir")"
    fi
    result="${cache[$key]}"

    if [[ -z "$result" ]]; then
      clear_pane "$pane"
      continue
    fi

    local num state checks review url
    IFS=$'\x1f' read -r num state checks review url <<<"$result"
    # Empty token values clear that key, so idle fields simply disappear.
    "$HERDR" pane report-metadata "$pane" --source "$SOURCE" \
      --token "pr=$num" --token "pr_state=$state" --token "pr_checks=$checks" \
      --token "pr_review=$review" --token "pr_url=$url" >/dev/null
  done < <(jq -r '.result.agents[] | [.pane_id, (.foreground_cwd // .cwd)] | @tsv' <<<"$agents")
}

# bash 3.2 (macOS /bin/bash) lacks associative arrays; prefer a newer bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$b" ]] && { trap - EXIT; rmdir "$LOCK"; exec "$b" "$0" "$@"; }
  done
  echo "github-pr: bash >= 4 required" >&2
  exit 1
fi

while :; do
  rm -f "$DIRTY"
  refresh_all
  [[ -e "$DIRTY" ]] || break
done
