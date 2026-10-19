# herdr-rowhome-labs

Personal herdr customizations.

## plugins/github-pr

Shows the GitHub PR for each agent's current branch in the Agent sidebar.

For every agent pane, `refresh.sh` resolves the pane's cwd → git branch → `gh pr view`,
then reports pane tokens: `$pr` (`#123`), `$pr_state` (open/draft/merged/closed),
`$pr_checks` (✓/✗/● checks), `$pr_review` (approved/changes/in review).

Refreshes on server startup, whenever an agent changes status or is detected, and on
demand via the `rowhome.github-pr.refresh` action.

Requires `gh` (authenticated), `jq`, `git`, bash ≥ 4.

```bash
herdr plugin link ./plugins/github-pr
```

## config/

`sidebar-github-pr.toml` — Agent sidebar rows that render the PR tokens. Merge into
`~/.config/herdr/config.toml`, then `herdr server reload-config`.
