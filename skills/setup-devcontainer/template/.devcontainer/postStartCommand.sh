#!/usr/bin/env bash
# Runs as vscode on every container start, from both VS Code and start.sh.
# Everything here is idempotent: the Claude config dir is a volume that
# outlives containers, so this script meets its own earlier output.
set -euo pipefail

config_dir="${CLAUDE_CONFIG_DIR:?CLAUDE_CONFIG_DIR is set in the Dockerfile}"

# Permission prompts off by default. This is the container's own Claude config,
# so the host's settings are untouched. Only the one key is set, leaving any
# other settings you have added in the volume alone.
settings="${config_dir}/settings.json"
[ -s "${settings}" ] || echo '{}' > "${settings}"
jq '.permissions.defaultMode = "bypassPermissions"' "${settings}" > "${settings}.tmp"
mv "${settings}.tmp" "${settings}"

# __PROJECT_SETUP__

# Status, so a missing credential shows up now rather than mid-task.
if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  echo "Neither GH_TOKEN nor GITHUB_TOKEN is set: git push and gh (PRs, issues) will not work. Put GH_TOKEN=... in ~/.config/__PROJECT_REPO__/gh.env on the host and rerun start.sh."
fi

if [ ! -s "${config_dir}/.credentials.json" ]; then
  echo "Claude is not logged in yet: run 'claude' and log in once; the login persists across rebuilds."
fi
