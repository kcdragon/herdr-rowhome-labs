#!/usr/bin/env bash
# The prefix+a overlay: confirm (unless confirm_delete=false), run the project's
# Conductor archive script in the worktree, then have herdr delete it. The
# branch itself is kept.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

dir="${WORKTREE_DIR:?}"
workspace="${WORKTREE_WORKSPACE:?}"
name="$(basename "$dir")"
branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
archive="$(conductor_scripts "$dir" | jq -r '.archive // ""')"

finish() { printf '\n%s\nPress any key to close.' "$1"; read -rsn1; exit 0; }

# Pids of processes working in the worktree (the app, Claude, shells), apart
# from this script and its parents. With an argument, leaves out shells too.
worktree_pids() {
  local self=" " p=$$
  while (( p > 1 )); do self+="$p "; p="$(ps -o ppid= -p "$p" | tr -d ' ')"; done
  lsof -a -d cwd -Fpcn 2>/dev/null | awk -v dir="$dir" -v self="$self" -v noshells="${1:-}" '
    /^p/ { pid = substr($0, 2) }
    /^c/ { cmd = substr($0, 2) }
    /^n/ { n = substr($0, 2)
           if ((n == dir || index(n, dir "/") == 1) && index(self, " " pid " ") == 0 &&
               !(noshells && cmd ~ /^-?(ba|z|fi)?sh$/)) print pid }'
}

# A running app keeps writing into the checkout (logs, sqlite, asset builds),
# so herdr's delete would find it not empty. Stop everything first.
stop_worktree_processes() {
  local pids i
  pids="$(worktree_pids)"
  [[ -n "$pids" ]] || return 0
  echo "Stopping $(wc -w <<<"$pids" | tr -d ' ') processes running in it..."
  kill -TERM $pids 2>/dev/null
  # Interactive shells ignore TERM, so give the rest a moment to shut down
  # cleanly, then kill whatever's left.
  for i in {1..20}; do
    [[ -n "$(worktree_pids noshells)" ]] || break
    sleep 0.5
  done
  pids="$(worktree_pids)"
  [[ -n "$pids" ]] && kill -KILL $pids 2>/dev/null && sleep 0.5
  return 0
}

printf '\033[1mDelete worktree %s\033[0m (branch %s, which is kept)\n%s\n\n' "$name" "$branch" "$dir"
if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
  git -C "$dir" status --short | head -20
  finish "It has uncommitted changes. Commit or discard them first."
fi
if [[ -n "$archive" ]]; then
  echo "Archive script: $archive"
else
  echo "No archive script."
fi
if [[ "$confirm_delete" == true ]]; then
  printf '\nDelete it? [y/N] '
  read -rsn1 answer
  echo
  [[ "$answer" == [yY] ]] || exit 0
fi

if [[ -n "$archive" ]]; then
  printf '\n\033[1m$ %s\033[0m\n' "$archive"
  if ! (cd "$dir" && "${SHELL:-/bin/sh}" -c "$archive"); then
    finish "The archive script failed, so the worktree wasn't deleted."
  fi
fi

stop_worktree_processes
out="$("$HERDR" worktree remove --workspace "$workspace" 2>&1)" ||
  finish "herdr couldn't delete it: $(jq -r '.error.message // empty' <<<"$out" 2>/dev/null || echo "$out")"
