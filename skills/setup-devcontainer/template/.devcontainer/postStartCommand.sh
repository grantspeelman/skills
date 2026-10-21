#!/usr/bin/env bash
# Runs as vscode on every container start, from both VS Code and start.sh. The
# Dockerfile bakes it into the image as /usr/local/bin/devcontainer-post-start,
# and that copy is what runs: an edit here takes a rebuild.
# Everything here is idempotent: it runs on every start, and in start.sh's
# default mode the Claude config dir is a volume that outlives containers, so
# this script meets its own earlier output.
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
  if mountpoint -q "${config_dir}"; then
    echo "Claude is not logged in yet: run 'claude' and log in once; the login persists across rebuilds."
  else
    echo "Claude is not logged in yet: run 'claude' and log in. Without the shared config volume (--mount-workspace, VS Code), the login lasts until the container is recreated."
  fi
fi
