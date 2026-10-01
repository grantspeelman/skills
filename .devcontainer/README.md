# Dev container

A container for working on this repo with Claude Code, permission prompts off,
without handing Claude the rest of the machine.

## Getting in

**Terminal:** `.devcontainer/start.sh` builds the image (first run only), starts
the container, and drops you into a shell. Rerun it to get back in; the
container keeps running after you exit.

| Flag        | Effect |
|-------------|--------|
| `--rebuild` | Rebuild the image from scratch. This is also how Claude Code gets upgraded. |
| `--docker`  | Privileged mode with nested Docker. Read [Nested Docker](#nested-docker) first. |

**VS Code:** *Dev Containers: Reopen in Container*. VS Code builds its own
container from the same `docker-compose.yml`, separate from the one
`start.sh` builds.

First time only: run `claude` inside and log in. The login lives in the
`grantspeelman-skills-claude-config` volume, which every container for this repo
shares, so it survives rebuilds and covers both entry points.

## What the container can reach

| | |
|---|---|
| **Files** | Only this checkout, at `/workspace`. No host home directory, `~/.ssh` or `~/.claude`. |
| **SSH** | Your host ssh-agent, forwarded as a socket. `start.sh` starts an agent and runs `ssh-add` if it needs to. The container can use your key to sign, but it can't read or copy the key. GitHub's host keys are pinned in the image. |
| **GitHub API** | `GH_TOKEN` / `GITHUB_TOKEN`, passed through from the host environment. Use a fine-grained token scoped to this repo. |
| **Claude** | Its own config (the volume above), with `permissions.defaultMode = bypassPermissions`. Your host Claude settings are untouched. |
| **Network** | Unrestricted outbound. There's no egress firewall. |

Inside the container Claude has passwordless `sudo`. In the default,
unprivileged container that makes it root in a disposable box, not on your
machine.

## Skills are live

`~/.claude/skills` inside the container is a link to `/workspace/skills`, so a
skill you add or edit is available to the next `claude` session. There's no
install step.

## Commit checks

`lefthook.yml` runs `gitleaks` on staged changes before every commit made inside
the container. Commits made on the host skip the hook (it prints "Can't find
lefthook" and lets the commit through). CI scans the full history on every push
as a backstop.

## Nested Docker

`start.sh --docker` recreates the container as **privileged** and starts
`dockerd` inside it. A privileged container plus `sudo` is not a security
boundary: code running in it can get root on the host. Use it for the sessions
that need Docker, then run `start.sh` without the flag to go back to the
unprivileged container. VS Code never uses this mode.

## Changing the image

The image is `ubuntu:26.04`. Most tools come from Ubuntu's archive; `gh` and
`gitleaks` are too old there, so they're checksummed release binaries.

`container-structure-test.yaml` is the spec for the image. Each pinned tool has
a version test there, so when you bump a pin in the `Dockerfile` (version and
SHA-256), update its test in the same commit.

`smoke-test.sh` starts a real container the way `start.sh` does and checks it
end to end: SSH forwarding, Claude settings, the skills link, the commit hook,
nested Docker, and switching back to unprivileged. It runs in about 30 seconds
and cleans up after itself, using a throwaway Claude config volume so your login
is never touched.

CI (`.github/workflows/devcontainer-ci.yml`) runs both, plus a full-history
secret scan, on every push to `main` and every PR.
