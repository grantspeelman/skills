# Dev container

A container for working on __PROJECT__ with Claude Code, permission prompts off,
without handing Claude the rest of the machine.

## Getting in

**Terminal:** `.devcontainer/start.sh` builds the image (first run only), starts
the container, and drops you into a shell. By default the container works in
its own clone of the repo, which `start.sh` seeds from this checkout on the
first run (see [Two ways to get /workspace](#two-ways-to-get-workspace)). If the
repo the container works in has no `user.name` or `user.email`, it asks for
them (defaulting to this checkout's git config, then your global one), since
the container can't see `~/.gitconfig`. Rerun it to get back in; the container
keeps running after you exit.

| Flag        | Effect |
|-------------|--------|
| `--rebuild` | Run `git pull --ff-only` in this checkout, then rebuild the image from scratch. This is also how Claude Code gets upgraded. Stops if the pull fails, e.g. the branch has no upstream or has diverged. If the pull changes the `.devcontainer/` files to anything other than what's on the remote's default branch, it shows the diff and asks before running it, since this host runs that code (with no terminal to ask on, it stops). After a `--mount-workspace` or VS Code session this check protects nothing: the container could have changed the files on disk, `.git/config` and `.git/hooks`, which it relies on. It doesn't touch the container's clone. |
| `--docker`  | Privileged mode with nested Docker. Works with either way of getting `/workspace`. Read [Nested Docker](#nested-docker) first. |
| `--mount-workspace` | Mount this checkout read-write at `/workspace` instead of using the container's own clone. Read [Two ways to get /workspace](#two-ways-to-get-workspace) first. |
| `--reset`   | Delete the container's clone and seed it again from this checkout. It lists what in the clone isn't on GitHub (commits, commits only in reflogs, tags, notes, stashes, uncommitted files) first, and asks (with no terminal to ask on, it stops). Can't be combined with `--mount-workspace`. |
| `-- CMD...` | Run `CMD` in the container instead of a shell, e.g. `start.sh --rebuild -- claude --resume`. Must come last. |

Switching between the clone and `--mount-workspace`, or in and out of
`--docker`, recreates the container. The clone stays in its volume either way.

**VS Code:** *Dev Containers: Reopen in Container*. VS Code builds its own
container from `docker-compose.yml` and `compose.mount.yml`, separate from the
one `start.sh` builds. It mounts the checkout, like `--mount-workspace`, with
the same risks.

Run `claude` inside and log in. With `start.sh`'s own clone, the login lives in
the `__PROJECT__-claude-config` volume, which every default-mode
container for this repo shares, so you log in once and it survives rebuilds.
With `--mount-workspace` and in VS Code, the login isn't kept: you log in again
whenever the container is recreated.

## What the container can reach

| | |
|---|---|
| **Files** | By default, only its own clone of the repo (in a volume) and the Claude config volume. Nothing from the host is mounted. With `--mount-workspace` and in VS Code, this checkout, read-write, and no Claude config volume. Never the host home directory, `~/.ssh` or `~/.claude`. |
| **GitHub** | Only `GH_TOKEN=...` from `~/.config/__PROJECT_REPO__/gh.env` on the host, outside the checkout, for both `git push` and `gh`. A token exported in your shell isn't passed in. See [GitHub access](#github-access) for the permissions it should have. The `env_file` entry needs Docker Compose 2.24 or later. |
| **SSH** | None from `start.sh`: no ssh-agent is forwarded. VS Code forwards your host agent on its own (see below). |
| **Claude** | Its own config, with `permissions.defaultMode = bypassPermissions`. Your host Claude settings are untouched. |
| **Network** | Unrestricted outbound. There's no egress firewall. |

There's no `sudo` in the container, so Claude can't change the image's git
setup (hooks, credential helper) from inside. Anything the project needs
installed goes in the `Dockerfile`. For a one-off root shell, use
`docker compose exec --user root app bash` from the host, where Claude can't.

## Two ways to get /workspace

Claude runs with permission prompts off, so a prompt injection (in a web page,
an issue, a dependency's README) can run commands here. The container keeps
that away from your machine. What's left is how the container's work reaches
the host, and that depends on where `/workspace` comes from.

### The container's own clone (default)

`start.sh` gives the container a clone of the repo in a volume of its own, one
per checkout. On the first run, when the volume is empty, it streams a git
bundle of this checkout into the container and clones from it there. The
bundle holds `HEAD`, every branch and tag (unpushed ones included) and
`origin`'s branches as this checkout last fetched them, and nothing else. The
clone is on the branch (or detached commit) this checkout is on, with `origin`
set to this checkout's `origin`, minus any credentials in the URL. Data only
goes in: nothing in the container can write to this checkout or its `.git`.
A shallow or partial (`--filter`) checkout can't seed a full clone, so
`start.sh` stops and says so.

That happens once. Later runs leave the clone alone, and the container fetches
from GitHub itself. Its work leaves the same way: pushed to a branch and merged
through a PR. To see it on the host, `git fetch` or `git pull` here.

**Before you check out or pull a branch the container pushed, review its
`.devcontainer/` and the other files this host runs** (see the table under
[--mount-workspace and VS Code](#--mount-workspace-and-vs-code)). A pushed
branch can change any of them. For `.devcontainer/`, from the host:

```
git fetch origin
git diff origin/HEAD origin/<branch> -- .devcontainer
```

`start.sh` also checks `.devcontainer/` on every start: if it differs from the
remote's default branch as this checkout last fetched it
(`refs/remotes/origin/HEAD`, no network), it shows the diff and asks, and with
no terminal to ask on it stops. That catches changes to the compose files, the
`Dockerfile` and the rest of what `start.sh` runs, but not a changed `start.sh`
itself: the check runs inside the checked-out copy, which a pushed branch can
change to leave the check out. Hence the review before you check the branch
out. `--rebuild` doesn't have this gap, because the copy from before the pull
does its checking. The check doesn't cover files outside `.devcontainer/`, and
it also asks while you have your own uncommitted changes there.

What this costs:

- Files git doesn't track, such as a `.env` or local config, aren't in the
  bundle, so they never reach the clone. Neither do stashes, notes or other
  remotes' branches. Create what you need inside.
- Work in the clone that isn't pushed exists only in the volume.
  `docker compose ... down -v` (`--volumes`) deletes it, as does `--reset`.
  Plain `down`, `--rebuild` and switching modes keep it. The Claude login volume
  is external, so `down -v` leaves it alone.
- The clone's git identity is its own: `start.sh` asks for it the first time
  and after a `--reset`.

To start the clone over, run `start.sh --reset`. It fetches from GitHub inside
the container, then lists every commit that isn't on a remote branch, any
tags that origin doesn't have, notes, stashes, and uncommitted, untracked and
ignored files, and asks before deleting anything. If it can't fetch or can't
check something, it says so rather than reporting nothing. Without a terminal
to ask on, it stops and changes nothing.

To have Claude work on the dev container itself, there's nothing to switch on:
it edits `.devcontainer/` in its clone and opens a PR. Once that's merged,
`start.sh --rebuild` pulls it here and runs it. `--rebuild` still checks the
pull, because the token can push to the branch this checkout is on.

### --mount-workspace and VS Code

These mount this checkout at `/workspace`, read-write, with nothing on top. The
container can change any file in it, including files your host later runs:

| Path | Who runs it |
|---|---|
| `.git/hooks/` | Host git, on commit, checkout, merge and so on. |
| `.git/config` | Host git runs commands it names: `core.fsmonitor`, `core.sshCommand`, aliases, filters. |
| `.git/` generally | Host git trusts its objects, refs and other files too. |
| `.devcontainer/` | You run `start.sh`, and Docker and VS Code use the compose files, `Dockerfile` and `devcontainer.json`. |
| `.claude/`, `CLAUDE.md`, `.vscode/`, CI workflows, build scripts | Claude, VS Code, CI and your build tools on the host. |

So a prompt injection in this mode can plant code that runs on your machine the
next time you run git, `start.sh`, VS Code or a build here. `start.sh`
doesn't check `.devcontainer/` in this mode, and after a session in it, neither
that check nor `--rebuild`'s protects anything: the container could have
changed the `.git/config`, hooks and files they rely on. Use it when you
want to edit the same files as Claude, and review what changed before you run
anything against the checkout on the host. If you edit files in VS Code
yourself, you're accepting these risks.

The container also gets no shared Claude config in this mode, so nothing it
writes there carries over to default-mode containers.

In a git worktree, `.git` is a file pointing at a host path the container
can't see, so git doesn't work inside with `--mount-workspace`. The default
clone doesn't have this problem.

## GitHub access

`start.sh` forwards no ssh-agent. An agent signs as your own key, so a prompt
injection could push to every repo, and log in to every host, that key
reaches. The token reaches only what you give it.

Inside the container git rewrites GitHub SSH remotes (`git@github.com:...`) to
HTTPS and authenticates with `gh`, so an SSH `origin` copied from this checkout
works as it is, and a plain `git push` of a new branch works without `-u`.
Without `gh.env`, nothing in the container can push.

Create a [fine-grained token](https://github.com/settings/personal-access-tokens/new)
for this repo only, with:

| Permission | Access | Why |
|---|---|---|
| Contents | Read and write | `git fetch` and `git push` |
| Pull requests | Read and write | `gh pr create` and friends |
| Administration | **None** | With it, a prompt injection could delete the ruleset below |
| Workflows | None | Pushes that change `.github/workflows/` are rejected; push those from the host, so CI can't be rewritten from inside |

Add Issues or others as you need them, and give it an expiry.

The token can still push to `main`, so protect it with a
[ruleset](https://github.com/__PROJECT_REPO__/settings/rules): target the
default branch, require a pull request, block force pushes and deletion, and
add **no bypass**. A bypass for you also covers the token, since the token acts
as you. That means every change, from the host too, lands through a PR.

**VS Code** is the exception: Dev Containers forwards your host agent into its
container itself, and git there still uses HTTPS and the token, but anything
in the container can find the agent's socket and sign with your key. Use
`start.sh` when Claude reads untrusted content.

## Project toolchain

__PROJECT_TOOLCHAIN_DOCS__

## Commit checks

`lefthook.yml` runs `gitleaks` on staged changes before every commit made inside
the container. The hook is baked into the image (`.devcontainer/git-hooks/`,
enabled by `core.hooksPath` in `/etc/gitconfig`), so it runs in every mode and
nothing is installed into the repo's `.git/hooks`. Commits made on the host
aren't checked unless you install lefthook there yourself. CI scans the full
history on every push as a backstop.

## Nested Docker

`start.sh --docker` recreates the container as **privileged** and starts
`dockerd` inside it. A privileged container is not a security boundary: Claude
can use `dockerd` to become root in the container and then on the host, and
reach this checkout and everything else there, whichever way `/workspace` is
provided. Don't point Claude at untrusted content in this mode. Use it for the
sessions that need Docker, then run `start.sh` without the flag to go back to
the unprivileged container. VS Code never uses this mode.

## Changing the image

The image is `ubuntu:26.04`. Most tools come from Ubuntu's archive; `gh` and
`gitleaks` are too old there, so they're checksummed release binaries.

`container-structure-test.yaml` is the spec for the image. Each pinned tool has
a version test there, so when you bump a pin in the `Dockerfile` (version and
SHA-256), update its test in the same commit.

`smoke-test.sh` runs `start.sh` from a throwaway copy of the checkout and checks
it end to end: the seeded clone with nothing from the host mounted, seeding only
once, seeding from a detached `HEAD`, leaving stashes out, stopping on a
shallow checkout, the `.devcontainer/` check, `--reset` (listing work kept
only in a reflog, stopping without a terminal, refusing a partial clone), `--mount-workspace` as a plain
mount with no Claude config volume, no SSH agent and git over HTTPS with the
token, no `sudo`, Claude settings, the project toolchain, the commit hook, nested
Docker, and switching back to unprivileged. It cleans up after itself, using
its own compose project and a throwaway Claude config volume so your login and
clone are never touched.

CI (`.github/workflows/devcontainer-ci.yml`) runs both, plus a full-history
secret scan, on every push to `main` and every PR.
