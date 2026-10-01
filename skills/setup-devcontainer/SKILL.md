---
name: setup-devcontainer
description: >-
  Add a sandboxed dev container for running Claude Code with permission
  prompts off to the current repo, tailored to its languages, tools and
  services. Built from the gps-skills dev container: Ubuntu, forwarded
  ssh-agent, gitleaks pre-commit hook, structure test, smoke test and CI.
disable-model-invocation: true
argument-hint: "[project-slug]"
---

# Set up a dev container

Add a dev container to the repo you're in, built from the template in
`template/` beside this file, and tailor it so the repo's own build, test and
lint commands work inside it. The template is generic. Your job is to keep its
security posture as it is and add what this repo needs.

## What the template gives you

- `.devcontainer/` with a `Dockerfile` (Ubuntu, Node for Claude Code, Python,
  `gh`, `gitleaks`, `lefthook`, Docker for opt-in nesting), compose files,
  `start.sh`, `postStartCommand.sh`, `container-structure-test.yaml`,
  `smoke-test.sh` and a `README.md`. It doesn't include `ssh_known_hosts`;
  step 5 creates that file from the git host's published keys.
- `lefthook.yml`, which runs gitleaks on staged changes before each commit.
- `.github/workflows/devcontainer-ci.yml`, which builds the image, runs the
  structure test and smoke test, and scans the full history for secrets.

Leave these properties alone unless the user asks you to change them: only the
checkout is mounted, no host `~/.ssh` or `~/.claude`; the agent is forwarded
rather than the key; GitHub host keys are pinned; downloaded binaries are
pinned and SHA-256 checked; nested Docker stays opt-in and privileged only with
`--docker`; the Claude config is a named volume.

## Steps

### 1. Check where you are

- Work from the repo root (`git rev-parse --show-toplevel`).
- The project slug is `$ARGUMENTS` if given. Otherwise derive it from the repo
  name: lowercase, with anything other than `a-z0-9_-` replaced by `-`. It names
  the image, the Claude config volume, the compose project and the agent socket.
- If `.devcontainer/`, `lefthook.yml` or `.github/workflows/devcontainer-ci.yml`
  already exist, stop and show the user what's there. Ask whether to replace,
  merge into, or leave each one. Don't overwrite on your own.

### 2. Survey the repo

Find out what a developer needs to build, test and lint this repo. Read, don't
guess:

- Version files: `.tool-versions`, `mise.toml`, `.nvmrc`, `.node-version`,
  `.python-version`, `.ruby-version`, `go.mod`, `rust-toolchain(.toml)`,
  `.java-version`, `global.json`, `package.json` `engines` / `packageManager`.
- Manifests and lockfiles: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`,
  `bun.lockb`, `pyproject.toml`, `uv.lock`, `poetry.lock`, `requirements*.txt`,
  `Gemfile.lock`, `Cargo.lock`, `composer.lock`, `pom.xml`, `build.gradle*`,
  `mix.lock`, `*.csproj`.
- Existing CI workflows: their `setup-*` actions give versions, and their steps
  show the system packages and the real build/test commands.
- Existing `Dockerfile` / `docker-compose*.yml`: backing services (Postgres,
  Redis, MySQL, etc.) and their versions.
- `Makefile`, `justfile`, `Taskfile.yml`, `package.json` scripts, `bin/setup`,
  `README` / `CONTRIBUTING` setup sections: system libraries (`libpq-dev`,
  `build-essential`, `libvips` …) and CLIs (`terraform`, `kubectl`, `aws` …).
- The git remote: if it isn't GitHub, the pinned host keys and the GitHub
  Actions workflow need adapting (see step 5).

Then tell the user what you found in a short list: runtimes with versions,
package managers, system packages, services, extra CLIs, and the commands you'll
use to prove it works. Ask about anything ambiguous (two Node versions, a
service only some developers run) before building.

### 3. Render the template

```bash
<this skill's dir>/scripts/render.sh "$(git rev-parse --show-toplevel)" <slug>
```

It copies the template and fills in the slug. If it exits 3 it has listed the
files that already exist and written nothing; go back to step 1's question for
those. Use the files the user chose to merge into as references, and render
the rest by hand from `template/`.

The rendered files carry markers to replace (and remove once used):

| Marker | File | What goes there |
|---|---|---|
| `# __PROJECT_TOOLCHAIN__` | `Dockerfile` | Runtimes, package managers, system packages, CLIs |
| `# __PROJECT_SERVICES__` | `docker-compose.yml` | Backing services and the app service's env/`depends_on` |
| `# __PROJECT_SETUP__` | `postStartCommand.sh` | Idempotent dependency install |
| `# __PROJECT_SMOKE_TESTS__` | `smoke-test.sh` | Checks that the project builds/tests inside |
| `__PROJECT_TOOLCHAIN_DOCS__` | `README.md` | What was added and how to bump it |

`.devcontainer/ssh_known_hosts` isn't rendered at all. You create it in step 5.

No marker may survive: `grep -rn '__PROJECT' .devcontainer lefthook.yml .github`
must come back empty.

### 4. Tailor it

**Dockerfile (`# __PROJECT_TOOLCHAIN__`).** Follow the template's own rules:

- Take a tool from the Ubuntu archive (add it to the existing `apt-get install`
  list, kept alphabetical) when the archive's version satisfies the repo.
  Check with `apt-cache policy` in a `ubuntu:<template version>` container if
  unsure.
- Otherwise fetch the official release binary, pinned with `ARG <TOOL>_VERSION`
  and `ENV <TOOL>_SHA256_AMD64/ARM64`, verified with `sha256sum -c`, in the same
  shape as the `gh` and `gitleaks` blocks. Take checksums from the project's
  published checksum file or by downloading and hashing both architectures.
  **Never write a checksum you didn't get from a real download or a published
  file.** If you can't reach the network, leave a clearly failing placeholder
  and tell the user.
- For a runtime with its own installer (rustup, uv, a JDK tarball), pin the
  version and install system-wide (`/usr/local`, `/opt`) as root so `vscode`
  can use it, with `PATH` set via `ENV`.
- If the repo needs a Node major other than the archive's, install that Node
  from nodejs.org (pinned and checksummed) and drop `nodejs`/`npm` from the apt
  list, so one Node serves both the project and Claude Code.
- Drop `python3*` from the apt list only if the user says so. Claude uses it
  for scripts.
- Put a one-line "why" comment on each addition, like the existing blocks.

**Services (`# __PROJECT_SERVICES__`).** Add backing services as compose
services beside `app`, never baked into the image: image pinned to the version
the repo uses, a `healthcheck`, a named volume for data, and the app service
given `depends_on: {<svc>: {condition: service_healthy}}` plus the env vars the
app reads (e.g. `DATABASE_URL`). Use obviously-local dev credentials
(`postgres`/`postgres`), never real ones. Don't publish service ports to the
host unless the user asks.

**Dependencies (`# __PROJECT_SETUP__`).** Install project dependencies with the
lockfile-respecting command (`npm ci`, `pnpm install --frozen-lockfile`,
`bundle install`, `uv sync --frozen`, `go mod download` …). It runs on every
start, so make it cheap when nothing changed: skip it when a hash of the
lockfile matches one stored from the last run. If the dependency directory is
large and inside the checkout (e.g. `node_modules`), consider a named volume
for it in `docker-compose.yml` and say so in the README.

**Structure test.** Add a `commandTests` entry for every tool you added: exact
version for pinned binaries, series (`^v20\.`) for archive packages, following
the existing comments. Update the image-design comment at the top.

**Smoke test (`# __PROJECT_SMOKE_TESTS__`).** Add a few `in_container` checks
that prove the container is fit for the repo: dependencies installed, the
build or a fast test target passes, each service answers. Keep the total
runtime reasonable (the template's runs in about 30 seconds); pick a quick
target over the full suite.

**README.** Replace `__PROJECT_TOOLCHAIN_DOCS__` with a short section listing
what was added for this repo, which come from the archive and which are pinned,
and that a pin bump means updating the `Dockerfile` and the structure test
together.

**lefthook.** If the repo already uses lefthook, husky, pre-commit or another
hook manager, don't install a second one: add the gitleaks command to the
existing setup and drop `lefthook.yml` and `lefthook install` from the template,
then tell the user.

### 5. Pin the git host's SSH keys

The template doesn't ship host keys, so they're always fetched fresh. The
`Dockerfile` copies `.devcontainer/ssh_known_hosts` into the image and the build
fails without it. Create it like this for GitHub:

```bash
{
  echo "# GitHub SSH host keys, from https://api.github.com/meta (fetched $(date -u +%F))."
  curl -fsSL https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .'
} > .devcontainer/ssh_known_hosts
ssh-keygen -lf .devcontainer/ssh_known_hosts
```

Then check that every SHA256 fingerprint `ssh-keygen` prints matches the
fingerprints GitHub publishes at
<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints>.
The API and the docs page are two separate sources, so a match means the keys
weren't tampered with on the way in. If they don't match, or you can't reach
either source, stop and tell the user. Never write host keys from memory or
copy them from another repo.

**Not on GitHub:** do the same with the host's own official sources, for
example GitLab's published SSH host keys and fingerprints page. Change the
comment and the `github\.com ssh-ed25519` pattern in the structure test to
that host. Convert or drop the GitHub Actions workflow to match the repo's CI,
and ask the user which. If the host doesn't publish its keys anywhere official,
ask the user for the fingerprints instead of trusting a first `ssh-keyscan`.

Keep the actions pinned to commit SHAs as in the template.

### 6. Verify

Run what the environment allows, in this order, and report each result:

1. `bash -n` on every `.sh` file; `docker compose ... config --quiet` as in the
   workflow's first step.
2. `docker build -f .devcontainer/Dockerfile .`
3. `container-structure-test` against the image, if installed.
4. `.devcontainer/smoke-test.sh` (needs Docker and an ssh-agent).

If Docker isn't available, say plainly which steps didn't run and that CI will
be the first real build. Don't claim it works when it hasn't been built.

### 7. Hand over

Summarise for the user: what was added for this repo, any choices you made for
them, what you verified and what you couldn't, and the first-run steps
(`.devcontainer/start.sh`, then `claude` and log in once). Don't commit unless
they ask.
