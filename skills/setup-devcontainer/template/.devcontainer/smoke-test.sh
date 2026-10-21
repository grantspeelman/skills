#!/bin/bash
# End-to-end check of the dev container through start.sh itself. It runs from a
# throwaway copy of this checkout, a fresh repo with a known pushed commit, an
# unpushed one and an untracked file, so seeding has something definite to work
# with and your own checkout is never touched. It covers:
#   • --docker (default mode): nested Docker, plus the image's own setup: no
#     ssh-agent, git over HTTPS with GH_TOKEN, Claude settings, the commit
#     hook, the project's own checks
#   • default mode: the clone seeded from the checkout, no host mount, git config
#     writable inside, seeding only once, dropping back out of --docker
#   • --reset: lists unpushed work, including a commit only in a reflog, and
#     stops without a terminal; stops before deleting on a host with a promisor
#     remote; with a terminal (through `script`), stops on "n" and re-seeds on "y"
#   • --mount-workspace: a plain mount with nothing on top, writable .git/config,
#     no Claude config volume
#   • a clone whose git config can't be read: stops, and says so
#   • seeding from a detached HEAD, and stopping on a shallow checkout or one
#     that can't be bundled
#   • the .devcontainer/ check every start runs
# Runs in CI (.github/workflows/devcontainer-ci.yml) and locally alike. It uses
# its own compose project and a throwaway Claude config volume (never your real
# login's), and removes them on exit.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
# start.sh reads both, so its containers and volumes are this run's own.
export SMOKE_COMPOSE_PROJECT="__PROJECT__-smoke-$$"
export SMOKE_CLAUDE_VOLUME="$SMOKE_COMPOSE_PROJECT-claude-config"
export USER_UID="$(id -u)" USER_GID="$(id -g)"

WORK="$(mktemp -d)"
CHECKOUT="$WORK/checkout"
START="$CHECKOUT/.devcontainer/start.sh"
BASE=(docker compose -p "$SMOKE_COMPOSE_PROJECT" -f "$CHECKOUT/.devcontainer/docker-compose.yml")
CLONE=("${BASE[@]}" -f "$CHECKOUT/.devcontainer/compose.clone.yml")
DOCKER=("${CLONE[@]}" -f "$CHECKOUT/.devcontainer/compose.docker.yml")
in_container() { "${CLONE[@]}" exec -T --user vscode app bash -c "$1" </dev/null; }
# What's mounted where in the running container: "type destination name", a line
# each. Read into a variable before grepping, so grep -q can't SIGPIPE it.
mounts() {
    docker inspect "$("${BASE[@]}" ps -q app)" \
        --format '{{range .Mounts}}{{.Type}} {{.Destination}} {{.Name}}{{"\n"}}{{end}}'
}

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

# Separate projects for the detached and shallow checkouts below.
OTHER_PROJECTS=("$SMOKE_COMPOSE_PROJECT-detached" "$SMOKE_COMPOSE_PROJECT-shallow" "$SMOKE_COMPOSE_PROJECT-broken")

cleanup() {
    "${DOCKER[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
    for project in "${OTHER_PROJECTS[@]}"; do
        docker compose -p "$project" -f "$CHECKOUT/.devcontainer/docker-compose.yml" \
            -f "$CHECKOUT/.devcontainer/compose.clone.yml" down --volumes >/dev/null 2>&1 || true
    done
    # External, so `down --volumes` leaves it.
    docker volume rm "$SMOKE_CLAUDE_VOLUME" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# The working tree as it is, uncommitted changes included, without its history.
mkdir "$CHECKOUT"
git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    | tar -C "$REPO_ROOT" --null --ignore-failed-read -T - -cf - | tar -C "$CHECKOUT" -xf -
host_git() { git -C "$CHECKOUT" -c user.name=smoke -c user.email=smoke@example.com "$@"; }
host_git init -q -b main
host_git add -A
host_git commit -q --no-verify -m "smoke: pushed"
# .invalid never resolves, so fetches fail fast and offline; the remote-tracking
# ref stands in for what GitHub has.
host_git remote add origin https://github.invalid/octo/smoke.git
host_git update-ref refs/remotes/origin/main HEAD
# What start.sh checks .devcontainer/ against on every start.
host_git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# A stash must not reach the clone, not even as an object.
echo "smoke stash $$" > "$CHECKOUT/smoke-stash.txt"
host_git add smoke-stash.txt
host_git stash push -q
stash_blob="$(echo "smoke stash $$" | git hash-object --stdin)"
host_git switch -q -c smoke-branch
host_git commit -q --no-verify --allow-empty -m "smoke: unpushed on the host"
host_git config user.name "Smoke Host"
host_git config user.email host@example.com
echo "not committed" > "$CHECKOUT/smoke-untracked.txt"
host_head="$(git -C "$CHECKOUT" rev-parse HEAD)"

echo "# the .devcontainer/ check"
echo "# smoke" >> "$CHECKOUT/.devcontainer/compose.mount.yml"
if "$START" -- true </dev/null >"$WORK/check.log" 2>&1; then
    cat "$WORK/check.log" >&2; fail "start.sh ran a .devcontainer/ that differs from origin/main"
fi
grep -q 'differs from origin/main' "$WORK/check.log" || { cat "$WORK/check.log" >&2; fail "start.sh did not say why it stopped"; }
git -C "$CHECKOUT" checkout -q -- .devcontainer/compose.mount.yml
pass "start.sh stops on a .devcontainer/ that differs from the default branch"

echo "# default mode, privileged, with nested Docker"
"$START" --docker -- true </dev/null
pass "start.sh --docker started the container"

in_container 'docker info' >/dev/null || fail "dockerd is not running"
pass "dockerd started"

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

echo "# default mode: the container's own clone"
m="$(mounts)"
if grep -q '^bind ' <<<"$m"; then fail "something from the host is bind-mounted: $m"; fi
pass "nothing from the host is mounted"
grep -q '^volume /workspace ' <<<"$m" || fail "/workspace is not a volume"
[ "$(awk '$2 == "/home/vscode/.claude" { print $3 }' <<<"$m")" = "$SMOKE_CLAUDE_VOLUME" ] \
    || fail "the Claude config is not the throwaway volume"
pass "/workspace and the Claude config are volumes"

[ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$host_head" ] || fail "the clone's HEAD is not the checkout's"
[ "$(in_container 'git -C /workspace symbolic-ref --short HEAD')" = smoke-branch ] || fail "the clone is not on the checkout's branch"
[ "$(in_container 'git -C /workspace config --get remote.origin.url')" = https://github.invalid/octo/smoke.git ] \
    || fail "the clone's origin is not the checkout's"
in_container 'git -C /workspace rev-parse --verify --quiet refs/remotes/origin/main' >/dev/null \
    || fail "the clone lacks the checkout's remote-tracking branches"
in_container '[ -z "$(git -C /workspace status --porcelain)" ]' || fail "the seeded clone is not clean"
pass "clone seeded from the checkout: branch, HEAD, origin, remote branches"
in_container '[ ! -e /workspace/smoke-untracked.txt ]' || fail "an untracked host file reached the clone"
pass "untracked host files stay out"
in_container "! git -C /workspace cat-file -e $stash_blob 2>/dev/null" || fail "a host stash reached the clone"
pass "host stashes stay out"

in_container '
    set -e; cd /workspace
    git config --local user.name "Smoke Container"; git config --local user.email container@example.com
    git commit -q --allow-empty -m "smoke: container work"' || fail "can't set git config or commit in the clone"
[ "$(git -C "$CHECKOUT" config --local --get user.name)" = "Smoke Host" ] \
    || fail "the clone's git config reached the host checkout"
pass "git config and commits work in the clone, apart from the checkout"
container_head="$(in_container 'git -C /workspace rev-parse HEAD')"

echo "# back to unprivileged"
# The post-start setup runs from the image, so the clone can't break it.
in_container 'rm /workspace/.devcontainer/postStartCommand.sh'
"$START" -- true </dev/null
[ "$(docker inspect "$("${BASE[@]}" ps -q app)" --format '{{.HostConfig.Privileged}}')" = false ] \
    || fail "container still privileged without --docker"
pass "container recreated unprivileged"
in_container '! docker info >/dev/null 2>&1' || fail "dockerd running while unprivileged"
pass "no dockerd while unprivileged"
in_container '! command -v sudo' >/dev/null || fail "sudo is installed"
pass "no sudo"
[ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$container_head" ] || fail "the clone was seeded again"
pass "the clone survives the recreate and isn't seeded again"
pass "start.sh runs the image's post-start setup, not the clone's"
in_container 'git -C /workspace checkout -q -- .devcontainer/postStartCommand.sh'

echo "# a clone git can't read"
in_container 'echo "[broken" >> /workspace/.git/config'
if "$START" -- true </dev/null >"$WORK/unreadable.log" 2>&1; then
    cat "$WORK/unreadable.log" >&2; fail "start.sh went ahead with a clone whose config git can't read"
fi
in_container 'sed -i "\$d" /workspace/.git/config'
grep -q "git couldn't read its config" "$WORK/unreadable.log" \
    || { cat "$WORK/unreadable.log" >&2; fail "start.sh did not say the clone's config can't be read"; }
[ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$container_head" ] || fail "an unreadable clone was changed"
pass "stops on a clone whose config git can't read"

echo "# --reset"
# Work a reset dropped is only in the reflogs, and must still be listed.
in_container '
    set -e; cd /workspace
    git checkout -q --detach origin/main
    git commit -q --allow-empty -m "smoke: dropped by a reset"
    git reset -q --hard origin/main
    git checkout -q smoke-branch' || fail "can't make a commit only in a reflog"
if "$START" --reset -- true </dev/null >"$WORK/reset.log" 2>&1; then
    cat "$WORK/reset.log" >&2; fail "--reset went ahead without a terminal"
fi
grep -q 'smoke: container work' "$WORK/reset.log" || { cat "$WORK/reset.log" >&2; fail "--reset did not list the unpushed commit"; }
grep -q 'smoke: dropped by a reset' "$WORK/reset.log" || { cat "$WORK/reset.log" >&2; fail "--reset did not list the commit only in a reflog"; }
[ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$container_head" ] || fail "--reset changed the clone without asking"
pass "--reset lists unpushed work, reflogs included, and stops without a terminal"

# The partial-clone check runs before the listing, the prompt and the delete.
host_git config remote.origin.promisor true
if "$START" --reset -- true </dev/null >"$WORK/reset.log" 2>&1; then
    cat "$WORK/reset.log" >&2; fail "--reset went ahead from a partial clone"
fi
host_git config --unset remote.origin.promisor
grep -q 'partial clone' "$WORK/reset.log" || { cat "$WORK/reset.log" >&2; fail "--reset did not say the checkout is a partial clone"; }
if grep -q "Checking what isn't on GitHub" "$WORK/reset.log"; then
    cat "$WORK/reset.log" >&2; fail "--reset got as far as the listing from a partial clone"
fi
[ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$container_head" ] || fail "--reset changed the clone from a partial clone"
pass "--reset stops before deleting when the checkout has a promisor remote"

# util-linux script(1) gives start.sh a terminal to prompt on; skip where it's
# a different script(1).
if script -qec true /dev/null >/dev/null 2>&1; then
    printf -v reset_cmd '%q --reset -- true' "$START"
    if printf 'n\n' | script -qec "$reset_cmd" /dev/null >"$WORK/reset.log" 2>&1; then
        cat "$WORK/reset.log" >&2; fail "--reset went ahead on n"
    fi
    [ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$container_head" ] || fail "--reset changed the clone on n"
    pass "--reset stops on n"

    in_container 'touch /workspace/.git/smoke-junk'
    # y to the reset, then the defaults for user.name and user.email.
    printf 'y\n\n\n' | script -qec "$reset_cmd" /dev/null >"$WORK/reset.log" 2>&1 \
        || { cat "$WORK/reset.log" >&2; fail "--reset failed on y"; }
    [ "$(in_container 'git -C /workspace rev-parse HEAD')" = "$host_head" ] || fail "--reset did not seed the clone again"
    in_container '[ ! -e /workspace/.git/smoke-junk ]' || fail "--reset left the old clone's files"
    [ "$(in_container 'git -C /workspace config --local --get user.name')" = "Smoke Host" ] \
        || fail "start.sh did not set the clone's git identity from the checkout's"
    pass "--reset re-seeds on y, and start.sh asks for the clone's git identity"
else
    echo "skip - --reset with a terminal (needs util-linux script)"
fi

echo "# --mount-workspace"
if "$START" --mount-workspace --reset -- true </dev/null >/dev/null 2>&1; then
    fail "--reset was accepted with --mount-workspace"
fi
pass "--reset refused with --mount-workspace"
"$START" --mount-workspace -- true </dev/null
m="$(mounts)"
[ "$(grep -c ' /workspace' <<<"$m")" = 1 ] && grep -q '^bind /workspace ' <<<"$m" \
    || fail "/workspace is not one plain bind mount: $m"
in_container '[ -e /workspace/smoke-untracked.txt ]' || fail "/workspace is not the checkout"
pass "the checkout is mounted, with nothing on top"
if grep -q ' /home/vscode/.claude ' <<<"$m"; then fail "a Claude config volume is mounted"; fi
pass "no Claude config volume"
in_container 'git -C /workspace config --local smoke.mounted yes' || fail "can't write .git/config"
[ "$(git -C "$CHECKOUT" config --local --get smoke.mounted)" = yes ] || fail ".git/config written inside didn't reach the checkout"
pass ".git/config is writable, and shared with the host"

echo "# other checkouts"
# Each gets its own project, and so its own container and clone.
other() { SMOKE_COMPOSE_PROJECT="$2" "$1/.devcontainer/start.sh" -- true </dev/null; }
git clone -q "$CHECKOUT" "$WORK/detached"
git -C "$WORK/detached" checkout -q --detach
git -C "$WORK/detached" -c user.name=smoke -c user.email=smoke@example.com \
    commit -q --no-verify --allow-empty -m "smoke: detached"
other "$WORK/detached" "${OTHER_PROJECTS[0]}"
[ "$(docker compose -p "${OTHER_PROJECTS[0]}" -f "$CHECKOUT/.devcontainer/docker-compose.yml" \
        -f "$CHECKOUT/.devcontainer/compose.clone.yml" \
        exec -T --user vscode app git -C /workspace rev-parse HEAD </dev/null)" \
    = "$(git -C "$WORK/detached" rev-parse HEAD)" ] || fail "the clone is not at the checkout's detached HEAD"
pass "seeds from a detached HEAD"

git clone -q --depth 1 "file://$CHECKOUT" "$WORK/shallow"
if other "$WORK/shallow" "${OTHER_PROJECTS[1]}" >"$WORK/shallow.log" 2>&1; then
    cat "$WORK/shallow.log" >&2; fail "start.sh seeded from a shallow checkout"
fi
grep -q 'checkout is shallow' "$WORK/shallow.log" || { cat "$WORK/shallow.log" >&2; fail "start.sh did not say the checkout is shallow"; }
pass "stops on a shallow checkout"

# A checkout missing an object it needs: the bundle fails before anything else.
git clone -q "$CHECKOUT" "$WORK/broken"
echo "smoke broken $$" > "$WORK/broken/smoke-broken.txt"
git -C "$WORK/broken" add smoke-broken.txt
git -C "$WORK/broken" -c user.name=smoke -c user.email=smoke@example.com \
    commit -q --no-verify -m "smoke: broken"
broken_blob="$(git -C "$WORK/broken" rev-parse HEAD:smoke-broken.txt)"
rm "$WORK/broken/.git/objects/${broken_blob:0:2}/${broken_blob:2}"
if other "$WORK/broken" "${OTHER_PROJECTS[2]}" >"$WORK/broken.log" 2>&1; then
    cat "$WORK/broken.log" >&2; fail "start.sh seeded from a checkout missing an object"
fi
grep -q "Couldn't bundle this checkout" "$WORK/broken.log" || { cat "$WORK/broken.log" >&2; fail "start.sh did not say the bundle failed"; }
if compgen -G "$WORK/broken/.git/devcontainer-seed.*" >/dev/null; then fail "start.sh left its bundle directory behind"; fi
pass "stops on a checkout that can't be bundled, and cleans up"

echo "all smoke tests passed"
