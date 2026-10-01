#!/bin/bash
# Copy the dev container template into a target repo and fill in its name.
#   render.sh <target-repo> <project-slug>
# Refuses to overwrite: if any template file already exists in the target, it
# lists them and exits 3 without writing anything. Leaves the __PROJECT_*__
# tailoring markers in place for the skill to fill in.
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
    sed "s/__PROJECT__/${slug}/g" "$TEMPLATE/$f" > "$target/$f"
    [ -x "$TEMPLATE/$f" ] && chmod +x "$target/$f"
    echo "$f"
done
