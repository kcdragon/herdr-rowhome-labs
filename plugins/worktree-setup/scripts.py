"""Print a worktree's Conductor scripts as JSON: {"setup", "run": [...], "archive"}.

Usage: scripts.py <main checkout> <worktree>

Read the way Conductor does, key by key: the gitignored
.conductor/settings.local.toml (only in the main checkout), then
.conductor/settings.toml, then the legacy conductor.json.
"""
import json
import pathlib
import sys
import tomllib

root, worktree = map(pathlib.Path, sys.argv[1:3])


def toml_scripts(path):
    try:
        with open(path, "rb") as f:
            return tomllib.load(f).get("scripts", {})
    except (OSError, tomllib.TOMLDecodeError):
        return {}


def json_scripts(path):
    try:
        with open(path) as f:
            return json.load(f).get("scripts", {})
    except (OSError, ValueError):
        return {}


layers = [
    toml_scripts(root / ".conductor/settings.local.toml"),
    toml_scripts(worktree / ".conductor/settings.toml"),
    json_scripts(worktree / "conductor.json"),
]


def pick(key):
    return next((layer[key] for layer in layers if layer.get(key)), None)


def run_commands(run):
    # Either one command, or named scripts: [scripts.run.<name>] command = "...".
    if isinstance(run, str):
        return [run]
    if isinstance(run, dict):
        return [v["command"] for v in run.values() if isinstance(v, dict) and v.get("command")]
    return []


print(json.dumps({
    "setup": pick("setup") or "",
    "run": run_commands(pick("run")),
    "archive": pick("archive") or "",
}))
