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

## plugins/fetch-origin

Keeps `origin/main` current in every agent's repo, so reviewr's branch diff stops showing work
that has already merged. A merge on GitHub doesn't move your local `origin/main` until something
fetches.

Runs `git fetch --prune origin` for each repo with an agent (once per repo; worktrees share refs)
on server startup and whenever an agent changes status or is detected, at most every two minutes
per repo. After merging in GitHub's web UI while agents sit idle, run the
`rowhome.fetch-origin.fetch` action to fetch right away. It never touches your local `main`.

Squash merges need one more step: the branch's commits never become part of `main`, so reviewr
keeps diffing from where the branch started even after a fetch. So after fetching, for each agent
that isn't mid-turn, a worktree whose branch has no uncommitted or untracked changes and whose files
are identical to `origin/<default>` (i.e. everything on it has landed) has its branch moved to
`origin/<default>` with `git reset --soft`, which changes no files. The old commit is kept as
`refs/fetch-origin/<branch>`; undo with `git reset --soft refs/fetch-origin/<branch>`. A branch
with new commits since the squash merge is left alone: rebase it onto `origin/<default>` yourself,
or start follow-up work in a new worktree.

## plugins/worktree-setup

Lays out every new worktree (herdr's "New worktree", `prefix+shift+g`, or `herdr worktree
create`) using the project's Conductor scripts:

- tab `claude`: Claude, focused, with reviewr below it
- tab `app`: the project's setup script, then its run scripts

1. Fetches and fast-forwards the new branch to `origin/<default>` (herdr branches from the main
   checkout's possibly stale `HEAD`; fast-forward only, so nothing can be lost).
2. Opens an `app` tab that runs `scripts.setup`, then every `scripts.run` command
   side by side (`[scripts.run.<name>]` tables included). If setup fails, nothing runs and you get
   a notification; rerun with the command shown in the tab. Ctrl-C stops the run scripts.
3. Names the first tab `claude` and starts Claude there; that tab stays active (`agent_command`
   in `config/plugins/rowhome.worktree-setup/config.sh`). `reviewr-below` then adds reviewr under
   it; reviewr's own `auto_open` is off so it doesn't grab the first pane first.

Scripts are read like Conductor does, key by key: `.conductor/settings.local.toml` from the main
checkout, then `.conductor/settings.toml`, then `conductor.json`. No `CONDUCTOR_*` variables are
set — each repo works out its own per-worktree ports and databases.

**Deleting:** `prefix+a` (in a worktree) opens a confirm overlay, runs `scripts.archive` inside
the worktree, and only if it succeeds has herdr delete the checkout and close the workspace. The
branch is kept. It refuses worktrees with uncommitted changes. Herdr has no hook before its own
"Delete worktree checkout", which removes the checkout before anything could run there, so use
`prefix+a` for worktrees whose archive script matters.
