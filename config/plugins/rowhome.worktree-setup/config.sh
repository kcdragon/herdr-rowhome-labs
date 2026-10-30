# Command started in a new worktree's first pane (prefix+shift+g / "New worktree").
agent_command=claude
# First message sent to it, unless the repo has .herdr/prompt.local.md (main
# checkout) or .herdr/prompt.md. Empty sends nothing.
agent_prompt="$(cat <<'EOF'
You work through Basecamp 42 stories using the basecamp42 skill and MCP.

- Find this repo's Basecamp 42 project in .herdr/basecamp42.local in the main
  checkout (the parent of `git rev-parse --path-format=absolute --git-common-dir`).
  If that file is missing, find the project whose repo_url matches this repo (ask
  me if none does), write its name there, and make sure `.herdr/*.local*` is in
  that checkout's .git/info/exclude so it stays untracked.
- Given a story number: read the whole story with get_story, claim it, and work it.
- Given a task with no story: investigate first. Create a story in that project,
  claim it, and work it only if there's something to change (code, content,
  config). If the answer is just information or "nothing to fix", reply with that
  and don't create a story.
- Once you have a story, rename this worktree's branch with
  `git branch -m story-<number>-<slug>` and its herdr workspace with
  `herdr workspace rename "$HERDR_WORKSPACE_ID" story-<number>-<slug>`.
- Keep the story's status current as you go, and put the PR URL on it when you
  open one.
- Prove the change works, in the story: screenshots or a screen recording for UI
  changes; otherwise test output, a reproduction, or a comment summarizing the
  checks you ran and what they showed.

For now, reply with one line saying you are ready, and wait for a story or task.
EOF
)"
# Ask "Delete it? [y/N]" before deleting with prefix+a. Worktrees with
# uncommitted changes are always refused.
confirm_delete=false
