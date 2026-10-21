#!/bin/bash
# Build, start and attach to the dev container from a plain terminal.
#   --rebuild  git pull --ff-only, then rebuild the image from scratch (also how
#              Claude Code gets upgraded); asks first if the pull changes
#              .devcontainer/ to anything but the default branch's
#   --docker   privileged mode with nested Docker; see compose.docker.yml first
#   --maintain writable .devcontainer/, to work on the dev container itself
#   -- CMD...  run CMD in the container instead of bash, e.g. -- claude --resume
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

original_args=("$@")
rebuild=false
docker_mode=false
maintain_mode=false
command=(bash)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --rebuild) rebuild=true ;;
        --docker) docker_mode=true ;;
        --maintain) maintain_mode=true ;;
        --)
            shift
            if [ "$#" -gt 0 ]; then command=("$@"); fi
            break
            ;;
        *) echo "Usage: $(basename "$0") [--rebuild] [--docker] [--maintain] [-- CMD [ARG...]]" >&2; exit 64 ;;
    esac
    shift
done

# One container per checkout: key the compose project to the checkout path, so
# two checkouts never share (or recreate) each other's container. The name also
# differs from the one VS Code generates, so the two never disturb each other.
checkout_slug="$(printf '%s' "$(basename "$PROJECT_ROOT")" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')"
checkout_digest="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
COMPOSE_PROJECT="__PROJECT__-${checkout_slug}-${checkout_digest}"
SERVICE="app"
# docker-compose.yml mounts .git/hooks and .git/config read-only, which needs a
# real .git directory; in a worktree .git is a file pointing elsewhere.
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo -e "${RED}$PROJECT_ROOT/.git is not a directory (a git worktree?). The dev container needs a regular clone.${NC}" >&2
    exit 1
fi

# ── Update: --rebuild builds what's on the remote ───────────────────────────
if [ "$rebuild" = true ] && [ -z "${START_SH_PULLED:-}" ]; then
    # This copy predates the pull, so it's the one that can vet what comes in.
    # It trusts only the files on disk, which the container can't write, and the
    # remote: HEAD, the index and the rest of .git the container can.
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
    # The remote git pull uses, read now: the container can write .git/HEAD.
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

# ── Git identity: the container sees .git/config, not your ~/.gitconfig ─────
identity_changed=false
for key in user.name user.email; do
    if [ -n "$(git -C "$PROJECT_ROOT" config --local --get "$key" || true)" ]; then
        continue
    fi
    if [ ! -t 0 ]; then
        echo -e "${YELLOW}$key is not set in this repo's .git/config: commits inside the container will fail.${NC}"
        continue
    fi
    default="$(git -C "$PROJECT_ROOT" config --global --get "$key" || true)"
    read -r -p "Git $key for this repo${default:+ [$default]}: " value
    value="${value:-$default}"
    if [ -z "$value" ]; then
        echo -e "${RED}$key is required for commits inside the container.${NC}" >&2
        exit 1
    fi
    git -C "$PROJECT_ROOT" config --local "$key" "$value"
    identity_changed=true
done

COMPOSE=(docker compose -p "$COMPOSE_PROJECT"
    -f "$SCRIPT_DIR/docker-compose.yml")
if [ "$docker_mode" = true ]; then
    COMPOSE+=(-f "$SCRIPT_DIR/compose.docker.yml")
fi
if [ "$maintain_mode" = true ]; then
    COMPOSE+=(-f "$SCRIPT_DIR/compose.maintain.yml")
fi

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
GH_ENV_FILE="$HOME/.config/__PROJECT_REPO__/gh.env"
if [ ! -f "$GH_ENV_FILE" ]; then
    echo -e "${YELLOW}No $GH_ENV_FILE (GH_TOKEN=...): git push and gh inside the container will not work.${NC}"
elif [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
    echo -e "${YELLOW}GH_TOKEN/GITHUB_TOKEN in this shell isn't passed in; the container uses $GH_ENV_FILE.${NC}"
fi

if [ "$docker_mode" = true ]; then
    echo -e "${YELLOW}--docker: the container runs PRIVILEGED. With dockerd inside, it is not a boundary between Claude and this host.${NC}"
fi
if [ "$maintain_mode" = true ]; then
    echo -e "${YELLOW}--maintain: .devcontainer/ is writable, and this host runs it. Review changes to it before you next run start.sh.${NC}"
fi

# ── Build and start ──────────────────────────────────────────────────────────
if [ "$rebuild" = true ]; then
    echo -e "${GREEN}Rebuilding the image from scratch...${NC}"
    "${COMPOSE[@]}" build --pull --no-cache
    "${COMPOSE[@]}" up --detach --force-recreate
else
    # --build is a cache hit unless the Dockerfile changed; `up` recreates the
    # container only when its image or config changed (e.g. toggling --docker or
    # --maintain).
    up_args=(--detach --build)
    # git rewrote .git/config as a new file; a running container's bind mount
    # still shows the old one until it's recreated.
    if [ "$identity_changed" = true ]; then
        up_args+=(--force-recreate)
    fi
    "${COMPOSE[@]}" up "${up_args[@]}"
fi

if [ "$docker_mode" = true ]; then
    echo -e "${GREEN}Waiting for dockerd inside the container...${NC}"
    timeout=90
    until "${COMPOSE[@]}" exec -T "$SERVICE" docker info &>/dev/null; do
        timeout=$((timeout - 1))
        if [ "$timeout" -le 0 ]; then
            echo -e "${RED}dockerd did not start within 90s. Recent container logs:${NC}" >&2
            "${COMPOSE[@]}" logs --tail 40 "$SERVICE" >&2 || true
            exit 1
        fi
        sleep 1
    done
fi

"${COMPOSE[@]}" exec -T --user vscode "$SERVICE" .devcontainer/postStartCommand.sh

# %q so the line stays copy-pasteable from a checkout path containing spaces.
printf -v stop_command '%q ' "${COMPOSE[@]}"
echo -e "${GREEN}The container outlives this shell: rerun this script to get back in.${NC}"
echo -e "${GREEN}Stop it with: ${stop_command}down${NC}"

# Herdr can't see the agent inside the container, only `docker compose`, so
# name it on this host-side process. Set only for agents, never for a shell.
case "$(basename "${command[0]}")" in
    claude) export HERDR_AGENT=claude ;;
esac
exec "${COMPOSE[@]}" exec --user vscode "$SERVICE" "${command[@]}"
