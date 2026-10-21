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
diff in a pane, opened as a split below the agent. Configured to open on the `branch` scope
(commits since the base branch plus uncommitted changes); `u` switches to uncommitted only,
`3` shows the PR. `prefix+d` toggles it for the workspace.

## plugins/reviewr-below

Keeps a reviewr pane below the first agent of every tab. Runs on server startup and whenever
herdr detects a new agent, skipping tabs that already have a reviewr pane or whose agent isn't
in a git repo. Run the `rowhome.reviewr-below.ensure` action to restore panes you closed.

## plugins/new-task

Conductor-style workspaces. `prefix+a` asks for a branch name, then, for the focused pane's repo
(its main checkout, even from a worktree):

1. creates a git worktree for the branch from `origin/HEAD` (after a fetch), opened as a new
   herdr workspace grouped under the repo, and focuses it
2. exports Conductor's variables in that pane's shell: `CONDUCTOR_WORKSPACE_NAME`,
   `CONDUCTOR_WORKSPACE_PATH`, `CONDUCTOR_ROOT_PATH`, `CONDUCTOR_DEFAULT_BRANCH`,
   `CONDUCTOR_IS_LOCAL=1` and `CONDUCTOR_PORT` (the first of ten ports reserved for this
   worktree, starting at 55100)
3. runs the project's Conductor setup script there: `scripts.setup` from
   `.conductor/settings.local.toml` (read from the main checkout), `.conductor/settings.toml`,
   or `conductor.json`. If it fails, the agent isn't started
4. starts the agent (Claude by default) with no prompt, for you to type the first one

The variables only exist in that first pane; other panes in the workspace don't get them.
Defaults (agent kind, branch prefix) live in `config/plugins/rowhome.new-task/config.sh`.
Worktrees go under herdr's `worktrees.directory` (default `~/.herdr/worktrees`). Remove one with
herdr's "Delete worktree checkout" on the workspace row; Conductor `archive` scripts aren't run.
