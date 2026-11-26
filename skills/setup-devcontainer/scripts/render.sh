#!/bin/bash
# Copy the dev container template into a target repo and fill in its name.
#   render.sh <target-repo> <project-slug>
# __PROJECT__ becomes the slug, and __PROJECT_REPO__ the repo's owner/name from
# its origin remote (the slug if there's no remote).
# Refuses to overwrite: if any template file already exists in the target, it
# lists them and exits 3 without writing anything. Leaves the __PROJECT_*__
# tailoring markers in place for the skill to fill in. It does not create
# .devcontainer/ssh_known_hosts: the skill fetches and checks those keys itself.
# It adds .devcontainer/compose.ports.yml (start.sh writes it per checkout)
# and its temp files, compose.ports.yml.tmp-*, to the target's .gitignore,
# creating the file if need be.
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $(basename "$0") <target-repo> <project-slug>" >&2
    exit 64
fi

TEMPLATE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../template" && pwd )"
target="$( cd "$1" && pwd )"
slug="$2"

if ! [[ "$slug" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Project slug must be lowercase letters, digits, '-' or '_' (got '$slug')." >&2
    exit 64
fi

repo="$(git -C "$target" remote get-url origin 2>/dev/null || true)"
repo="${repo%.git}"
repo="$(printf '%s' "$repo" | sed -E 's#^.*[:/]([^/:]+/[^/:]+)$#\1#')"
if ! [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    repo="$slug"
fi

mapfile -t files < <(cd "$TEMPLATE" && find . -type f | sed 's|^\./||' | sort)

conflicts=()
for f in "${files[@]}"; do
    [ -e "$target/$f" ] && conflicts+=("$f")
done
if [ ${#conflicts[@]} -gt 0 ]; then
    echo "These files already exist in $target; nothing was written:" >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    exit 3
fi

for f in "${files[@]}"; do
    mkdir -p "$(dirname "$target/$f")"
    sed -e "s|__PROJECT_REPO__|${repo}|g" -e "s|__PROJECT__|${slug}|g" "$TEMPLATE/$f" > "$target/$f"
    [ -x "$TEMPLATE/$f" ] && chmod +x "$target/$f"
    echo "$f"
done

ignore="$target/.gitignore"
missing=()
for entry in .devcontainer/compose.ports.yml ".devcontainer/compose.ports.yml.tmp-*"; do
    grep -qxF "$entry" "$ignore" 2>/dev/null || missing+=("$entry")
done
if [ ${#missing[@]} -gt 0 ]; then
    # Onto a line of its own, even when the file doesn't end in a newline.
    if [ -s "$ignore" ] && [ -n "$(tail -c 1 "$ignore")" ]; then echo >> "$ignore"; fi
    printf '%s\n' "# The dev container's host ports; start.sh writes them per checkout." "${missing[@]}" >> "$ignore"
    echo ".gitignore"
fi
