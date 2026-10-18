# AGENTS.md

This repo is a Claude Code and Codex plugin (`gps-skills`) that packages a set of skills.

## Layout

- `skills/<name>/SKILL.md` – one folder per skill, with any scripts and assets beside it
- `.claude-plugin/plugin.json` – plugin manifest
- `.claude-plugin/marketplace.json` – marketplace listing
- `.codex-plugin/plugin.json` and `.agents/plugins/marketplace.json` – the same for Codex
- `skills/<name>/agents/openai.yaml` – optional Codex-only skill settings
- `README.md` – skill list and install steps

## Rules

- Each skill needs a `SKILL.md` with `name` and `description` frontmatter. The name must match the folder name.
- When adding, removing or renaming a skill, update the list in `README.md`.
- Keep the `name`, `version` and `description` in sync across the Claude and Codex manifests.
- Skills are shared by Claude Code and Codex. Claude-only frontmatter (`disable-model-invocation`, `argument-hint`) needs a Codex equivalent in `agents/openai.yaml`, and don't rely on a Claude-only tool without saying what to do without it.
- `skills/setup-devcontainer/template/` is a generic copy of `.devcontainer/`, `lefthook.yml` and the devcontainer CI workflow. When you change those, make the same change in the template. `ssh_known_hosts` is left out of the template on purpose; the skill fetches it.
- Don't commit secrets, customer data or PII. Use synthetic data in examples.
- Keep pull request titles and descriptions simple and high level, with a mermaid diagram where it helps explain the change.
