#!/bin/bash
# compose.ports.yml: the ports the dev container publishes on this host.
#   ports.sh write FILE [PORT...]    write FILE, unless it exists, publishing each
#                                    container PORT on 127.0.0.1
#   ports.sh check FILE COMPOSE...   exit 2 unless FILE changes nothing but the
#                                    app service's ports, all on loopback; 1 if
#                                    compose fails. COMPOSE is the docker
#                                    compose command without FILE
# start.sh runs both, and CI runs them to validate what `write` produces.
# COMPOSE_PROJECT, when set, is the caller's own compose project: ports its
# running container publishes count as free, so deleting the file and running
# start.sh again writes the same ones.
set -euo pipefail

usage="Usage: $(basename "$0") write FILE [PORT...] | check FILE COMPOSE..."

# Host ports that running containers publish, a "project|port" line each, with
# ranges (8000-8005) expanded. A stopped container holds none.
published_ports() {
    docker ps --format '{{.Label "com.docker.compose.project"}}|{{.Ports}}' 2>/dev/null \
        | while IFS='|' read -r project ports; do
            { grep -oE ':[0-9]+(-[0-9]+)?->' <<<"$ports" || true; } | sed 's/^://; s/->$//' \
                | while IFS=- read -r first last; do
                    port="$first"
                    while [ "$port" -le "${last:-$first}" ]; do
                        echo "$project|$port"
                        port=$((port + 1))
                    done
                done
        done || true
}

# Free unless picked or in $avoid, or claimed by another project's running
# container, or something on this host answers on it. The probe is bash's own
# /dev/tcp, so it needs no nc or lsof, on both loopbacks, since a server on
# localhost may listen on ::1 only. It probes this machine, so it can't see a
# remote DOCKER_HOST's ports, and it could stall where a firewall drops
# loopback traffic; if compose still finds a port taken, it says which.
port_free() {
    case " $picked $avoid " in *" $1 "*) return 1 ;; esac
    case "$own" in *" $1 "*) return 0 ;; esac
    case "$claimed" in *" $1 "*) return 1 ;; esac
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && ! (exec 3<>"/dev/tcp/::1/$1") 2>/dev/null
}

write() {
    local file="$1" port ports="" yaml="" host_port
    shift
    # A symlink counts too, even a dangling one, so check reports on it.
    if [ -e "$file" ] || [ -L "$file" ]; then return 0; fi
    for port in "$@"; do
        if ! [[ "$port" =~ ^0*[0-9]{1,5}$ ]] || [ "$((10#$port))" -lt 1 ] || [ "$((10#$port))" -gt 65535 ]; then
            echo "Not a port: $port" >&2
            exit 1
        fi
        port=$((10#$port))
        case " $ports " in *" $port "*) ;; *) ports+=" $port" ;; esac
    done
    own=" " claimed=" " picked="" avoid=""
    while IFS='|' read -r project port; do
        if [ -n "${COMPOSE_PROJECT:-}" ] && [ "$project" = "$COMPOSE_PROJECT" ]; then
            own+="$port "
        else
            claimed+="$port "
        fi
    done < <(published_ports)
    for port in $ports; do
        host_port="$port"
        avoid=""
        if ! port_free "$port"; then
            # The next free one, keeping clear of the other ports listed.
            avoid="$ports"
            host_port=$((port + 1))
            while [ "$host_port" -le 65535 ] && ! port_free "$host_port"; do
                host_port=$((host_port + 1))
            done
            if [ "$host_port" -gt 65535 ]; then
                echo "Port $port is taken on this host, and so is every one above it; nothing was written." >&2
                exit 1
            fi
            yaml+="      # $port was taken on this host when start.sh wrote this."$'\n'
        fi
        picked+=" $host_port"
        yaml+="      - \"127.0.0.1:$host_port:$port\""$'\n'
    done
    # Written beside it, then linked into place: ln fails rather than replace
    # a file another start.sh wrote meanwhile, and the file never shows up
    # half-written. A leftover from a kill is harmless: git ignores
    # compose.ports.yml.tmp-* and the .devcontainer/ check skips it.
    tmp="$(mktemp "$file.tmp-XXXXXX")"  # global: the EXIT trap outlives this function
    trap 'rm -f "$tmp"' EXIT
    {
        echo "# The ports this dev container publishes on this host, written by start.sh"
        echo "# on its first run. Yours to edit: start.sh never overwrites it, and git"
        echo "# ignores it. Changes take effect on the next start.sh run. Each entry is"
        echo "# \"127.0.0.1:<host port>:<container port>\": keep 127.0.0.1, so only this"
        echo "# machine can reach it. Set nothing else here: start.sh refuses the file if"
        echo "# it changes more than the app service's ports. VS Code doesn't use it."
        echo "services:"
        if [ -z "$yaml" ]; then
            echo "  # To publish a port, replace {} with:"
            echo "  #   ports:"
            echo "  #     - \"127.0.0.1:3000:3000\""
            echo "  app: {}"
        else
            echo "  app:"
            echo "    ports:"
            printf '%s' "$yaml"
        fi
    } > "$tmp"
    chmod 644 "$tmp"
    if ! ln "$tmp" "$file" 2>/dev/null && [ ! -e "$file" ]; then
        # No hard links on this filesystem: mv -n doesn't replace a file
        # either (GNU and BSD alike), though it checks and moves in two steps.
        mv -n "$tmp" "$file"
    fi
    rm -f "$tmp"
    if [ ! -e "$file" ]; then
        echo "Couldn't create $file." >&2
        exit 1
    fi
}

# These read compose's normalised output: two-space indents, services at the
# second level, ports in long form. If that format changes they find nothing
# to strip or to vouch for, so check fails closed: it refuses the file.

# The merged config minus the app service's ports. A value's continuation
# lines are always deeper than its key, so none can pose as "    ports:"
# under "  app:" (service keys sit at 4, their values' lines at 6 or more),
# and the skip ends at the next non-empty line of indent 4 or less, so it
# can't hide a real key. Empty lines don't end it: a multi-line value can
# hold them. Content under a top-level x- key could fake "  app:", but that
# key itself then differs, so the file is refused anyway.
without_app_ports() {
    awk '
        /^[^ ]/ { top = $0; in_app = 0 }
        top == "services:" && /^  [^ ]/ { in_app = ($0 == "  app:") }
        skip && (/^     / || /^$/) { next }
        { skip = 0 }
        in_app && $0 == "    ports:" { skip = 1; next }
        { print }'
}

# Succeeds when every port the app service publishes is on 127.0.0.1 or ::1.
# Reads raw lines by indent: items start at 6 ("      - "), their keys sit at
# 8, and anything deeper, or empty, is a value's continuation (a block scalar,
# say), which never counts as a key, so a value can't pass for host_ip. Each
# item needs exactly one host_ip, on loopback; any other line shape is refused.
app_ports_on_loopback() {
    awk '
        function done_item() {
            if (item && !(hosts == 1 && ok)) bad = 1
            item = 0; hosts = 0; ok = 0
        }
        /^[^ ]/ { top = $0; in_app = 0 }
        top == "services:" && /^  [^ ]/ { in_app = ($0 == "  app:") }
        in_ports && !/^     / && !/^$/ { done_item(); in_ports = 0 }
        in_ports {
            if (/^      - /) { done_item(); item = 1; items++; key = substr($0, 9) }
            else if (/^          / || /^$/) next
            else if (item && /^        [^ ]/) key = substr($0, 9)
            else { bad = 1; next }
            if (key ~ /^host_ip:/) {
                hosts++
                value = key
                sub(/^host_ip: */, "", value)
                gsub(/["\047]/, "", value)
                if (value == "127.0.0.1" || value == "::1") ok = 1
            }
            next
        }
        in_app && $0 == "    ports:" { in_ports = 1; had_ports = 1 }
        END { done_item(); exit (bad || (had_ports && !items)) }'
}

# Which parts of two configs ($1 and $2, files of the merged config minus the
# app's ports) differ, named only by fixed paths: top-level keys, service
# names, and services.<name>.<key>. Nothing deeper, and no values: compose
# resolves env_file and environment into the output, and interpolates
# list-form labels and environment into mapping keys, so either can hold
# GH_TOKEN. Each part is compared whole, so a change deep inside one still
# names it, and a path under one already named isn't repeated. Only lines at
# those indents start a part, and under services no value's lines sit that
# shallow, so a value can't pose as a path.
changed_paths() {
    awk '
        FNR == 1 { side++ }
        /^[^ ]/ { top = $0; sub(/:.*/, "", top); svc = ""; path = top }
        top == "services" && /^  [^ ]/ { svc = $0; sub(/^  /, "", svc); sub(/:.*/, "", svc); path = top "." svc }
        top == "services" && svc != "" && /^    [^ ]/ { key = $0; sub(/^    /, "", key); sub(/:.*/, "", key); path = "services." svc "." key }
        { part[side, path] = part[side, path] "\n" $0; seen[path] = 1 }
        END { for (p in seen) if (part[1, p] != part[2, p]) print p }' "$1" "$2" \
        | sort | awk '{ for (p in named) if (index($0, p ".") == 1) next; print; named[$0] = 1 }'
}

# The file is outside the .devcontainer/ check (it's this host's own), so this
# stands in: the merged config with and without it may differ only in the app
# service's ports, and those must be on loopback. Comparing compose's own
# result catches anything the file could do (other keys, services, top-level
# sections, !reset tags, anchors), without parsing YAML here.
# Exits 2 when the file does more than that, 1 when compose fails.
check() {
    local file="$1" with without command
    shift
    # Compose's own errors aren't shown: they can quote values, tokens
    # included. The message names the command that shows them.
    if ! without="$("$@" config 2>/dev/null)"; then
        printf -v command '%q ' "$@" config
        command="${command% }"
        echo "docker compose couldn't read the compose files. Its error isn't shown, as it can quote values such as tokens; to see it, run: $command" >&2
        exit 1
    fi
    if ! with="$("$@" -f "$file" config 2>/dev/null)"; then
        printf -v command '%q ' "$@" -f "$file" config
        command="${command% }"
        echo "docker compose couldn't read $file on top of the other compose files. Its error isn't shown, as it can quote values such as tokens; to see it, run: $command" >&2
        exit 1
    fi
    if [ "$(without_app_ports <<<"$with")" != "$(without_app_ports <<<"$without")" ]; then
        # Through pipes, not files, since both hold the resolved config,
        # tokens included. cat -v, so control characters in a file that may
        # not be the user's own can't rewrite what's shown.
        changed_paths <(without_app_ports <<<"$without") <(without_app_ports <<<"$with") \
            | sed 's/^/  /' | cat -v >&2 || true
        echo "$file changes more than the app service's ports: it changes what's listed above (values aren't shown, as they can hold secrets)." >&2
        exit 2
    fi
    if ! app_ports_on_loopback <<<"$with"; then
        echo "$file publishes a port on more than 127.0.0.1 or ::1, so others on your network could reach it." >&2
        exit 2
    fi
}

case "${1:-}" in
    write) [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 64; }; shift; write "$@" ;;
    check) [ "$#" -ge 3 ] || { echo "$usage" >&2; exit 64; }; shift; check "$@" ;;
    *) echo "$usage" >&2; exit 64 ;;
esac
