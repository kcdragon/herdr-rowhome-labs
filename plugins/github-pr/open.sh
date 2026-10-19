#!/usr/bin/env bash
# Open the PR reported for the focused pane in the browser.
set -euo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_PANE_ID:-}"
[[ -n "$pane" ]] || exit 0

url="$("$HERDR" pane get "$pane" | jq -r '.result.pane.tokens.pr_url // empty')"
[[ -n "$url" ]] || exit 0

case "$(uname)" in
  Darwin) open "$url" ;;
  *) xdg-open "$url" ;;
esac
