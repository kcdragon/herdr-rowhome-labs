#!/usr/bin/env bash
# Runs in the strip under a worktree's app pane: waits for the dev server to
# print its local URL, then shows it as a clickable link and puts it in the tab
# name ("app localhost:3000"), since logs scroll it away. Usage: url.sh <app pane>
set -uo pipefail
source "$(dirname "$0")/lib.sh"

app="${1:?app pane id}"
printf '\033[?25l\033[2J\033[H  \033[2mWaiting for the app’s URL…\033[0m'

out="$("$HERDR" pane wait-output "$app" \
  --regex 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:[0-9]+)?' 2>/dev/null)" || exit 0
url="$(jq -r '.result.matched_line // ""' <<<"$out" |
  grep -oE 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)(:[0-9]+)?' | head -1)"
url="${url/0.0.0.0/localhost}"
[[ -n "$url" ]] || exit 0

# OSC 8 makes it a link even in terminals that don't detect bare URLs.
printf '\033[2J\033[H  \033[1;4m\033]8;;%s\033\\%s\033]8;;\033\\\033[0m' "$url" "$url"

tab="$("$HERDR" pane get "$app" | jq -r '.result.pane.tab_id // empty')"
[[ -n "$tab" ]] && "$HERDR" tab rename "$tab" "app ${url#*://}" >/dev/null

# Keep the link on screen instead of dropping to a prompt.
while sleep 3600; do :; done
