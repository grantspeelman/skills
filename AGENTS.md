# AGENTS.md

This repo is a Claude Code plugin (`gps-skills`) that packages a set of skills.

## Layout

- `skills/<name>/SKILL.md` – one folder per skill, with any scripts and assets beside it
- `.claude-plugin/plugin.json` – plugin manifest
- `.claude-plugin/marketplace.json` – marketplace listing
- `README.md` – skill list and install steps

## Rules

- Each skill needs a `SKILL.md` with `name` and `description` frontmatter. The name must match the folder name.
- When adding, removing or renaming a skill, update the list in `README.md`.
- Keep the `name` in `plugin.json` and `marketplace.json` in sync.
- Don't commit secrets, customer data or PII. Use synthetic data in examples.
- `docx`, `pdf`, `pptx` and `xlsx` have their own `LICENSE.txt`. Leave those files unchanged.
