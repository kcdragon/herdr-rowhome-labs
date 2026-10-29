#!/usr/bin/env bash
# Startup hook. After a server restart herdr restores the layout but not the
# processes, so reviewr panes and app tabs come back as bare shells. Relaunch
# them. Panes already running something (e.g. after a live handoff) are left
# alone.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

snapshot="$("$HERDR" api snapshot | jq '.result.snapshot')" || exit 0

# True when pane $1 is running nothing but its login shell.
idle_shell() {
  "$HERDR" pane process-info --pane "$1" 2>/dev/null | jq -e '
    .result.process_info | .foreground_processes | length == 1
      and (.[0].argv[0] | ltrimstr("-") | test("^(ba|z|fi|k|tc|c)?sh$"))' >/dev/null
}

# reviewr: open a fresh plugin pane beside the restored shell, then close the
# shell, so the new pane takes its place in the layout.
jq -r '.panes[] | select(.label == "reviewr") | [.pane_id, .cwd] | @tsv' <<<"$snapshot" |
  while IFS=$'\t' read -r pane cwd; do
    idle_shell "$pane" || continue
    "$HERDR" plugin pane open --plugin persiyanov.reviewr --entrypoint pane --placement split \
      --target-pane "$pane" --direction down --cwd "$cwd" --no-focus >/dev/null &&
      "$HERDR" pane close "$pane" >/dev/null
  done

# App tabs: the first pane runs app.sh, the strip below it url.sh.
jq -r '.tabs[] | select(.label | test("^app( |$)")) | .tab_id' <<<"$snapshot" |
  while read -r tab; do
    panes=($(jq -r --arg t "$tab" '.layouts[] | select(.tab_id == $t) | .panes[].pane_id' <<<"$snapshot"))
    app="${panes[0]:-}"
    [[ -n "$app" ]] && idle_shell "$app" || continue
    "$HERDR" tab rename "$tab" app >/dev/null
    "$HERDR" pane run "$app" "bash $(printf %q "$PLUGIN_ROOT/app.sh")" >/dev/null
    url_pane="${panes[1]:-}"
    if [[ -z "$url_pane" ]]; then
      cwd="$(jq -r --arg p "$app" '.panes[] | select(.pane_id == $p) | .cwd' <<<"$snapshot")"
      url_pane="$("$HERDR" pane split "$app" --direction down --ratio 0.9 --cwd "$cwd" --no-focus 2>/dev/null |
        jq -r '.result.pane.pane_id // empty')"
    elif ! idle_shell "$url_pane"; then
      continue
    fi
    [[ -n "$url_pane" ]] &&
      "$HERDR" pane run "$url_pane" "bash $(printf %q "$PLUGIN_ROOT/url.sh") $app" >/dev/null
  done
