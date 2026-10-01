# gps-skills

Grant Petersen-Speelman's preferred minimum set of Claude Code skills.

## Skills

- [`auto-alignment-before-action`](skills/auto-alignment-before-action/SKILL.md) – before acting on a request that changes state, checks Claude and you agree on the goal.
- [`get-aligned`](skills/get-aligned/SKILL.md) – interviews you until you both agree on the goal and outcome.
- [`setup-devcontainer`](skills/setup-devcontainer/SKILL.md) – adds this repo's sandboxed Claude Code dev container to another repo, tailored to its stack. Run it with `/setup-devcontainer`; Claude won't invoke it on its own.
- [`unslop`](skills/unslop/SKILL.md) – removes AI writing patterns from prose so it sounds human.

## Install as a Claude Code plugin

In Claude Code, run:

```
/plugin marketplace add grantspeelman/skills
/plugin install gps-skills@gps-skills
```

Then restart Claude Code. To update later: `/plugin marketplace update gps-skills`.
