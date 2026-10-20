# herdr-rowhome-labs

Personal herdr setup, shared across machines.

## Set up a machine

```bash
git clone https://github.com/kcdragon/herdr-rowhome-labs.git ~/Code/herdr-rowhome-labs
~/Code/herdr-rowhome-labs/install.sh
```

`install.sh` is idempotent — re-run it after pulling changes. It:

- symlinks `config/config.toml` → `~/.config/herdr/config.toml` (backing up an existing file)
- installs/links every plugin in `plugins.txt` (GitHub plugins pinned to a ref; reinstalled
  when the ref changes), and uninstalls/unlinks any plugin not listed there — including a
  local plugin linked from an old clone path
- symlinks `config/plugins/<plugin-id>/*` into that plugin's config dir
- reloads the running herdr server

Herdr doesn't copy config or plugins to SSH machines, and plugins run on the machine running
the agents — so run `install.sh` on every machine. Requires `herdr`, `jq`, `git`.

To add or remove a plugin, edit `plugins.txt` and re-run `install.sh`. Plugins installed by
hand on a machine are removed on the next run.

## plugins/github-pr

Shows the GitHub PR for each agent's current branch in the Agent sidebar.

For every agent pane, `refresh.sh` resolves the pane's cwd → git branch → `gh pr view`,
then reports pane tokens: `$pr` (`#123`), `$pr_state` (open/draft/merged/closed),
`$pr_checks` (✓/✗/● checks), `$pr_review` (approved/changes/in review). The sidebar rows in
`config/config.toml` render them.

Refreshes on server startup, whenever an agent changes status or is detected, and on
demand via the `rowhome.github-pr.refresh` action.

Requires `gh` (authenticated), `jq`, `git`, bash ≥ 4.

## reviewr

[persiyanov/herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) — review the agent's
diff in a pane. `prefix+d` toggles it. Configured to open on the `branch` scope (commits since
the base branch plus uncommitted changes); `u` switches to uncommitted only, `3` shows the PR.
