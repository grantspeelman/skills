#!/bin/bash
# End-to-end check of the dev container through the same compose files start.sh
# uses: builds for the calling user's UID, runs the post-start setup, checks git
# reaches GitHub only through GH_TOKEN, then exercises nested Docker and dropping
# back out of it, the read-only paths, and making .devcontainer/ writable with
# compose.maintain.yml. Runs in CI (.github/workflows/devcontainer-ci.yml) and locally
# alike. It uses its own compose project and a throwaway Claude config volume
# (never your real login's), and removes them on exit.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT="__PROJECT__-smoke-$$"
BASE=(docker compose -p "$PROJECT"
    -f "$SCRIPT_DIR/docker-compose.yml"
    -f "$SCRIPT_DIR/smoke-test.compose.yml")
DOCKER=("${BASE[@]}" -f "$SCRIPT_DIR/compose.docker.yml")
in_container() { "${DOCKER[@]}" exec -T --user vscode app bash -c "$1"; }

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

cleanup() {
    "${DOCKER[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

export USER_UID="$(id -u)" USER_GID="$(id -g)"
export SMOKE_CLAUDE_VOLUME="$PROJECT-claude-config"

echo "# privileged, with nested Docker"
"${DOCKER[@]}" up --detach --build --quiet-pull
timeout=90
until "${DOCKER[@]}" exec -T app docker info >/dev/null 2>&1; do
    timeout=$((timeout - 1))
    [ "$timeout" -gt 0 ] || { "${DOCKER[@]}" logs --tail 40 app >&2; fail "dockerd did not start"; }
    sleep 1
done
pass "dockerd started"

in_container '.devcontainer/postStartCommand.sh' >/dev/null
pass "postStartCommand.sh ran"

[ "$(in_container 'id -u')" = "$USER_UID" ] || fail "vscode UID does not match host UID $USER_UID"
pass "vscode runs as host UID $USER_UID"

in_container '[ -z "${SSH_AUTH_SOCK:-}" ] && ! ssh-add -l >/dev/null 2>&1' || fail "an ssh-agent reaches the container"
pass "no ssh-agent forwarded"

[ "$(in_container 'git ls-remote --get-url git@github.com:octo/repo.git')" = https://github.com/octo/repo.git ] \
    || fail "git does not rewrite GitHub SSH remotes to HTTPS"
pass "GitHub SSH remotes go over HTTPS"

in_container 'printf "protocol=https\nhost=github.com\n\n" | GH_TOKEN=smoke-token GIT_TERMINAL_PROMPT=0 git credential fill' \
    | grep -qx 'password=smoke-token' || fail "git does not authenticate to GitHub with GH_TOKEN"
pass "git authenticates to GitHub with GH_TOKEN"

[ "$(in_container 'jq -r .permissions.defaultMode "$CLAUDE_CONFIG_DIR/settings.json"')" = bypassPermissions ] \
    || fail "bypassPermissions not set"
pass "Claude defaults to bypassPermissions"

# __PROJECT_SMOKE_TESTS__

[ "$(in_container 'git -C /workspace config core.hooksPath')" = /usr/local/share/git-hooks ] \
    || fail "git does not use the image's hooks"
pass "git uses the image's hooks"

in_container '
    set -e; git init -q /tmp/t; cp /workspace/lefthook.yml /tmp/t/; cd /tmp/t
    git config user.email smoke@example.com; git config user.name smoke
    printf "token = \"ghp_%s\"\n" "$(head -c 300 /dev/urandom | tr -dc A-Za-z0-9 | head -c 36)" > leak.txt
    git add leak.txt; ! git commit -qm leak >/dev/null 2>&1' || fail "gitleaks hook let a token through"
pass "gitleaks hook blocks a token"

in_container 'docker run --rm --quiet hello-world' | grep -q 'Hello from Docker!' || fail "nested docker run failed"
pass "nested docker run works"

echo "# back to unprivileged"
"${BASE[@]}" up --detach
[ "$(docker inspect "$("${BASE[@]}" ps -q app)" --format '{{.HostConfig.Privileged}}')" = false ] \
    || fail "container still privileged without compose.docker.yml"
pass "container recreated unprivileged"
"${BASE[@]}" exec -T --user vscode app bash -c '! docker info >/dev/null 2>&1' || fail "dockerd running while unprivileged"
pass "no dockerd while unprivileged"

echo "# read-only paths, unprivileged"
in_unprivileged() { "${BASE[@]}" exec -T --user "$1" app bash -c "$2"; }
in_unprivileged vscode '! command -v sudo' >/dev/null || fail "sudo is installed"
pass "no sudo"
for path in .git/config .git/hooks/smoke-plant .devcontainer/smoke-plant; do
    in_unprivileged vscode "! touch /workspace/$path 2>/dev/null" || fail "/workspace/$path is writable"
done
pass "host-executed paths are read-only"
in_unprivileged vscode '! git -C /workspace config core.fsmonitor "touch /tmp/pwned" 2>/dev/null' \
    || fail "git config could be changed"
pass "git config can't be changed"
in_unprivileged root 'command -v mount' >/dev/null || fail "no mount binary to test remounting with"
for path in .git/hooks .git/config .devcontainer; do
    in_unprivileged root "! mount -o remount,rw,bind /workspace/$path 2>/dev/null" \
        || fail "root could remount /workspace/$path read-write"
done
pass "even root can't remount them read-write"

echo "# --maintain"
MAINTAIN=("${BASE[@]}" -f "$SCRIPT_DIR/compose.maintain.yml")
"${MAINTAIN[@]}" up --detach
"${MAINTAIN[@]}" exec -T --user vscode app bash -c \
    'touch /workspace/.devcontainer/smoke-plant && rm /workspace/.devcontainer/smoke-plant' \
    || fail ".devcontainer/ is not writable with compose.maintain.yml"
pass ".devcontainer/ writable with --maintain"
"${BASE[@]}" up --detach
in_unprivileged vscode '! touch /workspace/.devcontainer/smoke-plant 2>/dev/null' \
    || fail ".devcontainer/ still writable after leaving --maintain"
pass "read-only again without --maintain"

echo "all smoke tests passed"
