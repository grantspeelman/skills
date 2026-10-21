#!/bin/bash
# Build, start and attach to the dev container from a plain terminal. By default
# the container works in its own clone of this repo, in a volume, seeded once
# from this checkout; nothing from the checkout is mounted.
#   --rebuild          git pull --ff-only, then rebuild the image from scratch
#                      (also how Claude Code gets upgraded); asks first if the
#                      pull changes .devcontainer/ to anything but the default
#                      branch's
#   --docker           privileged mode with nested Docker; see compose.docker.yml
#   --mount-workspace  mount this checkout read-write instead of using the clone;
#                      the container can then write files this host runs
#   --reset            discard the clone and seed it again from this checkout;
#                      lists what isn't on GitHub and asks first
#   -- CMD...          run CMD in the container instead of bash, e.g. -- claude --resume
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

usage="Usage: $(basename "$0") [--rebuild] [--docker] [--mount-workspace | --reset] [-- CMD [ARG...]]"
original_args=("$@")
rebuild=false
docker_mode=false
mount_mode=false
reset=false
command=(bash)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rebuild) rebuild=true ;;
        --docker) docker_mode=true ;;
        --mount-workspace) mount_mode=true ;;
        --reset) reset=true ;;
        --)
            shift
            if [ "$#" -gt 0 ]; then command=("$@"); fi
            break
            ;;
        *) echo "$usage" >&2; exit 64 ;;
    esac
    shift
done
# The mounted checkout is the host's own; there's no clone to reset.
if [ "$mount_mode" = true ] && [ "$reset" = true ]; then
    echo -e "${RED}--reset discards the container's own clone, which --mount-workspace doesn't use.${NC}" >&2
    echo "$usage" >&2
    exit 64
fi

# One container per checkout: key the compose project to the checkout path, so
# two checkouts never share (or recreate) each other's container or clone. The
# name also differs from the one VS Code generates, so the two never disturb
# each other. smoke-test.sh sets SMOKE_COMPOSE_PROJECT to keep its run apart.
checkout_slug="$(printf '%s' "$(basename "$PROJECT_ROOT")" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
checkout_digest="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
COMPOSE_PROJECT="${SMOKE_COMPOSE_PROJECT:-skills-${checkout_slug}-${checkout_digest}}"
SERVICE="app"
# The same name compose.clone.yml gives the external volume.
CLAUDE_VOLUME="${SMOKE_CLAUDE_VOLUME:-grantspeelman-skills-claude-config}"

# ── Update: --rebuild builds what's on the remote ───────────────────────────
# The container's clone isn't this checkout, but its token can push branches
# this checkout pulls, and with --mount-workspace (or VS Code) the container
# writes this checkout directly. Either way, this host runs .devcontainer/ next.
if [ "$rebuild" = true ] && [ -z "${START_SH_PULLED:-}" ]; then
    # This copy predates the pull, so it's the one that can vet what comes in.
    # It trusts only the files on disk and the remote, never HEAD, the index or
    # the rest of .git, which a container with the checkout mounted can write.
    devcontainer_tree() {
        local dir tree
        # Nothing when the pull removed it or swapped it for a file or symlink.
        if [ ! -d "$PROJECT_ROOT/.devcontainer" ] || [ -L "$PROJECT_ROOT/.devcontainer" ]; then
            return 0
        fi
        dir="$(mktemp -d)"
        # A throwaway index, so the real one (and its stat cache) plays no part.
        tree="$(GIT_INDEX_FILE="$dir/index" git -C "$PROJECT_ROOT" add --force -- .devcontainer \
            && GIT_INDEX_FILE="$dir/index" git -C "$PROJECT_ROOT" write-tree)" || { rm -rf "$dir"; return 1; }
        rm -rf "$dir"
        git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$tree:.devcontainer" || true
    }
    stop_rebuild() {
        echo -e "${RED}$1${NC}" >&2
        if [ "$(git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$old_head:.devcontainer" || true)" = "$before" ]; then
            echo -e "${RED}The checkout is already fast-forwarded; to go back: git reset --hard $old_head${NC}" >&2
        else
            # Resetting to it would put those files on disk.
            echo -e "${RED}HEAD already differed from the files on disk before the pull: look into it before you run start.sh again.${NC}" >&2
        fi
        exit 1
    }
    old_head="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    before="$(devcontainer_tree)"
    # The remote git pull uses, read before the pull can change it.
    branch="$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short HEAD || true)"
    remote="$(git -C "$PROJECT_ROOT" config --get "branch.$branch.remote" || echo origin)"
    echo -e "${GREEN}Pulling the latest changes (fast-forward only)...${NC}"
    if ! git -C "$PROJECT_ROOT" pull --ff-only; then
        echo -e "${RED}git pull --ff-only failed: sort out the branch, then rerun.${NC}" >&2
        exit 1
    fi
    after="$(devcontainer_tree)"
    if [ -z "$after" ] || [ "$(git -C "$PROJECT_ROOT" cat-file -t "$after")" != tree ]; then
        stop_rebuild "Stopped: the pull removed .devcontainer/ or made it something other than a directory."
    fi
    # Anyone who can push to this branch (the container's token, for one) can
    # change .devcontainer/, and this host runs it. The remote's default branch
    # only changes through a PR; anything else needs your eyes.
    if [ "$after" != "$before" ]; then
        # The remote names its default branch and that branch's tip: "ref:
        # refs/heads/<name>\tHEAD", then "<sha>\tHEAD".
        default_head="$(git -C "$PROJECT_ROOT" ls-remote --symref "$remote" HEAD 2>/dev/null || true)"
        default_branch="$(awk '$1 == "ref:" && $3 == "HEAD" { sub("^refs/heads/", "", $2); print $2 }' <<<"$default_head")"
        default_sha="$(awk '$1 != "ref:" && $2 == "HEAD" { print $1 }' <<<"$default_head")"
        # Fetch it for the objects, then use that exact sha: an exact match, so
        # an old default-branch commit (from before a fix) doesn't pass either.
        if [ "$remote" = . ] || [ -z "$default_branch" ] || [ -z "$default_sha" ] \
            || ! git -C "$PROJECT_ROOT" fetch --quiet "$remote" "refs/heads/$default_branch" \
            || [ "$(git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$default_sha:.devcontainer" || true)" != "$after" ]; then
            # --text and no drivers, so attributes can't hide a file; cat -v, so
            # control characters and \r can't hide lines.
            diff_args=(--no-pager diff --text --no-textconv --no-ext-diff
                --src-prefix=a/.devcontainer/ --dst-prefix=b/.devcontainer/ "$before" "$after")
            git -C "$PROJECT_ROOT" "${diff_args[@]}" --stat | cat -v
            git -C "$PROJECT_ROOT" "${diff_args[@]}" | cat -v
            echo -e "${YELLOW}The pull changes the .devcontainer/ that runs now (above) to something other than $remote/${default_branch:-<default branch>}. This host runs that code next.${NC}"
            answer=""
            if [ -t 0 ]; then
                read -r -p "Run it? [y/N] " answer || true
            fi
            if [ "$answer" != y ] && [ "$answer" != Y ]; then
                stop_rebuild "Stopped without running the new .devcontainer/."
            fi
        fi
    fi
    # The pull may have changed this script; run the new copy.
    START_SH_PULLED=1 exec "$SCRIPT_DIR/start.sh" "${original_args[@]}"
fi

COMPOSE=(docker compose -p "$COMPOSE_PROJECT"
    -f "$SCRIPT_DIR/docker-compose.yml")
if [ "$mount_mode" = true ]; then
    COMPOSE+=(-f "$SCRIPT_DIR/compose.mount.yml")
else
    COMPOSE+=(-f "$SCRIPT_DIR/compose.clone.yml")
fi
if [ "$docker_mode" = true ]; then
    COMPOSE+=(-f "$SCRIPT_DIR/compose.docker.yml")
fi
# Runs a command in the container. Its stdin is the caller's, so callers that
# don't feed it anything pass </dev/null, or it eats input meant for a prompt.
in_app() { "${COMPOSE[@]}" exec -T --user vscode "$SERVICE" "$@"; }

USER_UID="$(id -u)"
USER_GID="$(id -g)"
if [ "$USER_UID" -eq 0 ] || [ "$USER_GID" -eq 0 ]; then
    echo -e "${YELLOW}Running as root: building the image for UID/GID 1000:1000 instead, so the image's root user is not remapped.${NC}"
    USER_UID=1000
    USER_GID=1000
fi
export USER_UID USER_GID

# ── GitHub: the token is the container's only git credential ────────────────
# No ssh-agent is forwarded: it would sign as your own key, which reaches every
# repo and host that key can. git pushes over HTTPS with GH_TOKEN instead.
GH_ENV_FILE="$HOME/.config/grantspeelman/skills/gh.env"
if [ ! -f "$GH_ENV_FILE" ]; then
    echo -e "${YELLOW}No $GH_ENV_FILE (GH_TOKEN=...): git push and gh inside the container will not work.${NC}"
elif [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
    echo -e "${YELLOW}GH_TOKEN/GITHUB_TOKEN in this shell isn't passed in; the container uses $GH_ENV_FILE.${NC}"
fi

if [ "$docker_mode" = true ]; then
    echo -e "${YELLOW}--docker: the container runs PRIVILEGED. With dockerd inside, it is not a boundary between Claude and this host.${NC}"
fi
if [ "$mount_mode" = true ]; then
    echo -e "${YELLOW}--mount-workspace: the container can write this checkout, including files this host later runs: .git/hooks and .git/config (run by host git), .devcontainer/ (run by start.sh and Docker), and anything else your tools load from here. Review changes before you run git, start.sh or other tools here again.${NC}"
    echo -e "${YELLOW}The Claude login isn't kept in this mode: log in again whenever the container is recreated.${NC}"
    # In a worktree .git is a file naming a host path the container can't see.
    if [ ! -d "$PROJECT_ROOT/.git" ]; then
        echo -e "${YELLOW}$PROJECT_ROOT/.git is not a directory (a git worktree?): git won't work inside the container.${NC}"
    fi
else
    # External (see compose.clone.yml), so compose won't create it. A no-op
    # when it exists.
    docker volume create "$CLAUDE_VOLUME" >/dev/null
fi

# ── Build and start ──────────────────────────────────────────────────────────
if [ "$rebuild" = true ]; then
    echo -e "${GREEN}Rebuilding the image from scratch...${NC}"
    "${COMPOSE[@]}" build --pull --no-cache
    "${COMPOSE[@]}" up --detach --force-recreate
else
    # --build is a cache hit unless the Dockerfile changed; `up` recreates the
    # container only when its image or config changed (e.g. toggling --docker or
    # --mount-workspace). The clone's volume outlives the container either way.
    "${COMPOSE[@]}" up --detach --build
fi

# The entrypoint exits if dockerd fails, taking the container with it, so wait
# before running anything else in there.
if [ "$docker_mode" = true ]; then
    echo -e "${GREEN}Waiting for dockerd inside the container...${NC}"
    timeout=90
    until "${COMPOSE[@]}" exec -T "$SERVICE" docker info &>/dev/null </dev/null; do
        timeout=$((timeout - 1))
        if [ "$timeout" -le 0 ]; then
            echo -e "${RED}dockerd did not start within 90s. Recent container logs:${NC}" >&2
            "${COMPOSE[@]}" logs --tail 40 "$SERVICE" >&2 || true
            exit 1
        fi
        sleep 1
    done
fi

# ── The container's own clone ────────────────────────────────────────────────
if [ "$mount_mode" = false ]; then
    # seeded: a finished seed. empty: a new volume. other: anything else, such
    # as an interrupted seed; only --reset clears it.
    # shellcheck disable=SC2016 # expanded in the container
    state="$(in_app bash -c '
        if [ -n "$(git -C /workspace config --local --get devcontainer.seeded 2>/dev/null)" ]; then echo seeded
        elif [ -z "$(ls -A /workspace)" ]; then echo empty
        else echo other; fi' </dev/null)"

    if [ "$reset" = true ] && [ "$state" != empty ]; then
        # Everything --reset would destroy that GitHub doesn't have. It runs in
        # the container, so it fetches with the container's token and never
        # touches this checkout.
        # shellcheck disable=SC2016 # expanded in the container
        survey='
            cd /workspace
            if [ ! -e .git ]; then
                echo "No git repo in the work volume, only these files:"
                ls -A
                exit 0
            fi
            found=false
            section() { if [ -n "$2" ]; then printf "%s\n%s\n" "$1" "$2"; found=true; fi; }
            if git remote get-url origin >/dev/null 2>&1; then
                # --prune, so a branch deleted on GitHub no longer counts as pushed.
                GIT_TERMINAL_PROMPT=0 git fetch --quiet --prune origin \
                    || echo "Could not fetch from origin: comparing with the remote branches last fetched."
            else
                echo "No origin remote: nothing here is on GitHub."
            fi
            count="$(git rev-list --count HEAD --branches --not --remotes 2>/dev/null || echo 0)"
            if [ "$count" -gt 0 ]; then
                section "$count commit(s) not on any remote branch (newest 20):" \
                    "$(git log --oneline --decorate -n 20 HEAD --branches --not --remotes)"
            fi
            section "Stashes:" "$(git stash list)"
            section "Uncommitted, untracked and ignored files:" "$(git status --porcelain --ignored)"
            [ "$found" = true ] || echo "Nothing found that is not on GitHub."
        '
        echo -e "${YELLOW}--reset deletes everything in the container's clone. Checking what isn't on GitHub...${NC}"
        # cat -v: the container wrote these names, so control characters can't
        # rewrite what you see.
        in_app bash -c "$survey" </dev/null 2>&1 | cat -v
        if [ ! -t 0 ]; then
            echo -e "${RED}Stopped: --reset needs a terminal to confirm on. The clone is unchanged.${NC}" >&2
            exit 1
        fi
        answer=""
        read -r -p "Delete the clone above and seed it again from this checkout? [y/N] " answer || true
        if [ "$answer" != y ] && [ "$answer" != Y ]; then
            echo -e "${RED}Stopped. The clone is unchanged.${NC}" >&2
            exit 1
        fi
        # As root, so nothing the container made unwritable survives. The
        # volume's root stays, with the vscode ownership it took from the image.
        "${COMPOSE[@]}" exec -T --user root "$SERVICE" find /workspace -mindepth 1 -delete </dev/null
        state=empty
    fi

    case "$state" in
        seeded) ;;
        empty)
            # Seed once, from what this checkout has, unpushed branches included.
            # Data only flows in: the bundle goes to the container's stdin, and
            # nothing in the container can write back here. After this the clone
            # fetches from GitHub itself.
            echo -e "${GREEN}Seeding the container's clone from this checkout...${NC}"
            if ! seed_head="$(git -C "$PROJECT_ROOT" rev-parse --verify --quiet HEAD)"; then
                echo -e "${RED}This checkout has no commits to seed the container's clone from.${NC}" >&2
                exit 1
            fi
            seed_branch="$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short HEAD || true)"
            # The URL as written, not as this host's insteadOf rules rewrite it;
            # the image has its own rules for GitHub.
            origin_url="$(git -C "$PROJECT_ROOT" config --get remote.origin.url || true)"
            # shellcheck disable=SC2016 # expanded in the container
            seed='
                set -euo pipefail
                branch="$1" head="$2" origin_url="$3"
                cd /workspace
                bundle="$(mktemp)"
                trap "rm -f \"$bundle\"" EXIT
                cat > "$bundle"
                git -c init.defaultBranch=seed init -q
                # Branches and tags, plus the branches of origin as this checkout
                # last saw them, so the clone knows what is already pushed.
                git fetch -q --update-head-ok "$bundle" "+refs/heads/*:refs/heads/*" \
                    "+refs/tags/*:refs/tags/*" "+refs/remotes/origin/*:refs/remotes/origin/*" \
                    "^refs/remotes/origin/HEAD"
                if [ -n "$origin_url" ]; then
                    git remote add origin "$origin_url"
                fi
                if [ -n "$branch" ] && git show-ref --verify --quiet "refs/heads/$branch"; then
                    git symbolic-ref HEAD "refs/heads/$branch"
                    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                        git branch --quiet --set-upstream-to "origin/$branch"
                    fi
                else
                    git update-ref --no-deref HEAD "$head"
                fi
                git reset --quiet --hard
                # Last, so an interrupted seed is never taken for a finished one.
                git config devcontainer.seeded true
            '
            git -C "$PROJECT_ROOT" bundle create -q - --all \
                | in_app bash -c "$seed" seed "$seed_branch" "$seed_head" "$origin_url"
            if [ -z "$origin_url" ]; then
                echo -e "${YELLOW}This checkout has no origin remote, so neither does the clone: work in it can't be pushed.${NC}"
            fi
            ;;
        *)
            echo -e "${RED}The container's /workspace has files but no finished clone (an interrupted seed?). Rerun with --reset to clear it and seed again.${NC}" >&2
            exit 1
            ;;
    esac
fi

# ── Git identity: the container can't see your ~/.gitconfig ─────────────────
# It goes in the repo the container works in: the clone's own .git/config by
# default, this checkout's with --mount-workspace.
if [ "$mount_mode" = true ]; then
    repo_git=(git -C "$PROJECT_ROOT")
    where="this repo's .git/config"
else
    repo_git=(in_app git -C /workspace)
    where="the container's clone"
fi
for key in user.name user.email; do
    if [ -n "$("${repo_git[@]}" config --local --get "$key" </dev/null || true)" ]; then
        continue
    fi
    if [ ! -t 0 ]; then
        echo -e "${YELLOW}$key is not set in $where: commits inside the container will fail.${NC}"
        continue
    fi
    # This checkout's own setting first, then your global one.
    default="$(git -C "$PROJECT_ROOT" config --get "$key" || true)"
    read -r -p "Git $key for $where${default:+ [$default]}: " value
    value="${value:-$default}"
    if [ -z "$value" ]; then
        echo -e "${RED}$key is required for commits inside the container.${NC}" >&2
        exit 1
    fi
    "${repo_git[@]}" config --local "$key" "$value" </dev/null
done

in_app .devcontainer/postStartCommand.sh </dev/null

# %q so the line stays copy-pasteable from a checkout path containing spaces.
printf -v stop_command '%q ' "${COMPOSE[@]}"
echo -e "${GREEN}The container outlives this shell: rerun this script to get back in.${NC}"
echo -e "${GREEN}Stop it with: ${stop_command}down${NC}"
if [ "$mount_mode" = false ]; then
    echo -e "${YELLOW}Don't add -v (--volumes) to that: it deletes the container's clone, and any work in it that isn't pushed. (The Claude login is in an external volume, which it leaves alone.)${NC}"
fi

# Herdr can't see the agent inside the container, only `docker compose`, so
# name it on this host-side process. Set only for agents, never for a shell.
case "$(basename "${command[0]}")" in
    claude) export HERDR_AGENT=claude ;;
esac
# A terminal only when there is one, so `start.sh -- CMD` also works from a script.
exec_args=(--user vscode)
if [ ! -t 0 ]; then
    exec_args+=(-T)
fi
exec "${COMPOSE[@]}" exec "${exec_args[@]}" "$SERVICE" "${command[@]}"
