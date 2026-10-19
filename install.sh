#!/usr/bin/env bash
# Apply this repo's herdr setup to the current machine. Safe to re-run.
#
#   - symlinks config/config.toml to ~/.config/herdr/config.toml
#   - symlinks config/plugins/<id>/* into each plugin's config dir
#   - installs / links the plugins listed in plugins.txt, and removes the rest
#   - reloads the running herdr server, if any
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
HERDR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"

command -v herdr >/dev/null || { echo "herdr not found; install it first: https://herdr.dev" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

# Symlink $1 -> $2, backing up a real file that's in the way.
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    return
  fi
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    mv "$dst" "$dst.bak-$(date +%Y%m%d%H%M%S)"
    echo "backed up $dst"
  fi
  ln -sfn "$src" "$dst"
  echo "linked $dst"
}

link "$REPO/config/config.toml" "$HERDR_CONFIG/config.toml"

list_plugins() { herdr plugin list --json | jq -c '.result.plugins'; }

# Declared plugins as JSON: GitHub sources and local manifest paths.
declared="$(grep -Ev '^[[:space:]]*(#|$)' "$REPO/plugins.txt" | jq -R -s --arg repo "$REPO" '
  [split("\n")[] | select(length > 0) | [splits("[[:space:]]+")]] as $rows
  | { github: [$rows[] | select(.[0] == "github") | .[1]],
      local:  [$rows[] | select(.[0] == "local")  | "\($repo)/\(.[1])/herdr-plugin.toml"] }')"

# Remove registered plugins plugins.txt doesn't list. This also drops a local
# plugin linked from an old clone path before it's relinked from this one.
while IFS=$'\t' read -r id kind source; do
  if [[ "$kind" == "github" ]]; then
    herdr plugin uninstall "$id" >/dev/null
    echo "uninstalled $source"
  else
    herdr plugin unlink "$id" >/dev/null
    echo "unlinked $source"
  fi
done < <(list_plugins | jq -r --argjson d "$declared" '
  .[] | (.source.owner + "/" + .source.repo + (if .source.subdir then "/" + .source.subdir else "" end)) as $gh
      | .manifest_path as $m
      | select(if .source.kind == "github" then ($d.github | index($gh) | not)
               else ($d.local | index($m) | not) end)
      | [.plugin_id, .source.kind, (if .source.kind == "github" then $gh else .manifest_path end)] | @tsv')

plugins="$(list_plugins)"

while read -r kind target ref; do
  [[ -z "$kind" || "$kind" == \#* ]] && continue
  case "$kind" in
    github)
      # Reinstall when missing or pinned to a different ref.
      current="$(jq -r --arg t "$target" '
        .[] | select(.source.kind == "github")
            | select((.source.owner + "/" + .source.repo + (if .source.subdir then "/" + .source.subdir else "" end)) == $t)
            | .source.requested_ref // "none"' <<<"$plugins")"
      if [[ "$current" == "$ref" ]]; then
        echo "ok $target@$ref"
        continue
      fi
      [[ -n "$current" ]] && herdr plugin uninstall "$target" >/dev/null
      herdr plugin install "$target" --ref "$ref" --yes >/dev/null
      echo "installed $target@$ref"
      ;;
    local)
      dir="$REPO/$target"
      manifest="$dir/herdr-plugin.toml"
      if jq -e --arg m "$manifest" 'any(.[]; .manifest_path == $m)' <<<"$plugins" >/dev/null; then
        echo "ok $target"
        continue
      fi
      herdr plugin link "$dir" >/dev/null
      echo "linked $target"
      ;;
    *)
      echo "plugins.txt: unknown kind '$kind'" >&2
      exit 1
      ;;
  esac
done <"$REPO/plugins.txt"

# Per-plugin config files, e.g. config/plugins/persiyanov.reviewr/config.toml.
for dir in "$REPO"/config/plugins/*/; do
  id="$(basename "$dir")"
  dest="$(herdr plugin config-dir "$id")"
  for f in "$dir"*; do
    link "$f" "$dest/$(basename "$f")"
  done
done

if herdr status server >/dev/null 2>&1; then
  herdr server reload-config >/dev/null && echo "reloaded herdr config"
fi
