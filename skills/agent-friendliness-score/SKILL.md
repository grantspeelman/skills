---
name: agent-friendliness-score
description: >-
  Score a repo out of 100 on how safely AI coding agents can work in it, and
  end with the top three fixes. Measures whether the repo catches a plausible
  but wrong change by planting bugs in a separate worktree, timing the tests
  and testing the docs with a fresh agent. Costs real time and agent usage.
  Work in progress.
disable-model-invocation: true
---

# Agent-friendliness score

> **Work in progress.** Scores and verdict bands are not calibrated. Read them
> as a structured opinion backed by evidence, and say so in every report.

Score one repo on one question: **if an agent makes a plausible but wrong
change, will the repo catch it?** Five categories, 20 points each:
Verification, Feedback speed, Context, Consistency and Guardrails.

Every run is the full assessment. There are no lighter or deeper modes. Don't
run mutation testing or replay old pull requests. A mutation score the repo
already reports counts as evidence.

If the user named a package or path, score that. Otherwise score the whole repo.

Read these before scoring. They are part of this procedure:

- [references/checks.md](references/checks.md): how to run each measured check.
- [references/scoring.md](references/scoring.md): what each score means, and
  the verdict bands.

## Rules for the whole run

- Never push, open a pull request, or change the scored repo's working tree,
  index or branches. All edits happen in a separate worktree.
- Don't commit seeded changes. Apply each one with `git apply`, test it, then
  restore the worktree. No commit means no commit hooks run.
- Don't copy `.env` files, credentials or other secret files into the worktree
  or a report. If tests need them, mark the affected checks "not measured"
  unless the user supplies values that are safe for testing.
- If tests appear to reach production or shared services, stop and ask before
  running anything. Do the same if a run does something the plan didn't cover.
- Never guess a result. A check that could not run is "not measured".
- Reports go only in the save folder under the home directory, never in the
  scored repo. Paraphrase code and review comments where you can, because
  reports may quote private code. If you see a secret, don't repeat it.

## 1. Read the repo

Read-only. Find the stack, the test command, the commands CI runs, and how the
repo documents its setup. Note the current commit and whether the working tree
has uncommitted changes, because only the commit gets scored.

Look for services the tests may touch: Docker Compose files, database and
queue config, non-localhost URLs in test config, required environment
variables, and HTTP calls without a recording or stub library.

**Don't open test files yet.** You may list their paths and read test config.
Step 4 depends on writing bugs before seeing what the tests check.

## 2. Show the plan and confirm once

Show one plan and wait for one confirmation:

```text
Repo:       payments-api at 4f2a91c (uncommitted changes are not scored)
Tests:      bin/test, in a worktree outside the repo
Install:    bundle install (runs dependency install scripts)
Services:   local Postgres from docker-compose.yml. No external URLs found.
Seeded:     10 bugs, plus 5 planted convention violations
Agents:     2 fresh agents for the docs check
Other:      npx jscpd for duplication; read-only gh calls for CI history
Budget:     about 45 minutes, stopping at 60. Test runs: about 18.
Saved to:   ~/.agent-friendliness-score/payments-api-1a2b3c4d/ (may quote code)
```

Estimate time from CI history when you can. Otherwise say the estimate is
unknown until the first test run. The budget in the plan is the limit, and
[references/checks.md](references/checks.md) says how to stay inside it without
asking again. If the user declines, stop. If they change something, follow it.

## 3. Set up

Create the save folder and a worktree outside the repo. The `-c` flag stops the
repo's `post-checkout` hook from running.

```bash
root_commit=$(git rev-list --max-parents=0 HEAD | tail -1)
repo_id="$(basename "$(git rev-parse --show-toplevel)")-${root_commit:0:8}"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
save_dir="$HOME/.agent-friendliness-score/$repo_id/$stamp"
mkdir -p "$save_dir/seeded" && chmod -R go-rwx "$HOME/.agent-friendliness-score"
worktree=$(mktemp -d)/repo
git -c core.hooksPath=/dev/null worktree add --detach "$worktree" HEAD
git config --local --get core.hooksPath > "$save_dir/hooks-path-before" || true
```

Install dependencies in the worktree the way the repo documents, with `HUSKY=0`
and `LEFTHOOK=0` set so install scripts don't rewrite the git config the worktree
shares with the repo. If install fails, record why. It counts against Feedback
speed only if the repo's docs are at fault, as
[references/checks.md](references/checks.md) explains.

## 4. Write the seeded bugs, then run the measured checks

Run these in order, as [references/checks.md](references/checks.md) describes:

1. Write the seeded bugs from the code and docs, before reading any test.
2. Run the baseline twice and record timings.
3. Run the seeded bugs.
4. Run the planted convention violations.
5. Run the two fresh-agent checks.
6. Run the consistency counts.
7. Read CI and review history with `gh`, if available.

Restore the worktree between runs, and check you are in it first:

```bash
git -C "$worktree" checkout -- . && git -C "$worktree" clean -fd
```

If the baseline fails or there are no tests, carry on and score that. Don't
abort. A repo with no tests is a real result: Verification is 0.

## 5. Read the static evidence

Now read the tests. Collect the static evidence each category in
[references/scoring.md](references/scoring.md) asks for, including a sample of
tests with weak or no assertions and tests that mirror the implementation.

## 6. Score

Apply [references/scoring.md](references/scoring.md). Label every piece of
evidence **static** or **measured**. Measured results decide the score, even
when they are worse than the static evidence suggests.

## 7. Choose the top three fixes

Rank by points gained, and put Verification first on a tie. Each fix must name
the metric it moves, the current and target values, and roughly how many points
it's worth. Make fixes about this repo and about classes of mistake. "Add tests
for these ten patches" only games the rerun, so don't suggest it. Don't apply
any fix. This skill only reports.

## 8. Report, save and clean up

Show the report in this shape. The data here is made up.

```markdown
# Agent-friendliness: payments-api at 4f2a91c

**70/100: Agents can work here with review.**
Work in progress: scores are not calibrated.

| Category       | Score | Assessed | Main evidence                                 |
|----------------|-------|----------|-----------------------------------------------|
| Verification   | 15    | 20       | measured: 7 of 10 seeded bugs caught          |
| Feedback speed | 15    | 20       | measured: relevant tests in 3m 40s            |
| Context        | 10    | 20       | measured: 4 of 6 answers correct              |
| Consistency    | 15    | 20       | measured: 4.1% duplication (low confidence)   |
| Guardrails     | 15    | 20       | measured: 4 of 5 planted violations caught    |

## Evidence
One section per category. List each item with its label, static or measured,
and each check marked not measured or N/A with the reason.

## Seeded bugs
A table of bug, risk category, caught or missed, and what caught it.

## Top three fixes
1. Add request tests for permission checks on refund endpoints. Moves the
   seeded catch rate from 70% to 90% (Verification 15 to 20, +5 points).

## Since the last run
Total 60 to 70. Verification 10 to 15. Seeded bugs: 6 of 10 reused still
caught, 2 of 3 new caught. Commit 91bd03e to 4f2a91c.
```

If anything went unmeasured, show the total as points assessed, such as
`60/80 assessed`, so a gap doesn't read as a low score.

Compare against the newest earlier folder for this repo, if there is one.

Save to `$save_dir`:

- `report.md`: the report above.
- `result.json`: commit, date, scores, assessed points, raw metrics, and the
  searches used for Consistency, so the next run can compare and repeat them.
- `seeded/NN-<risk-category>.patch`: each seeded bug, with its result recorded
  in `result.json`.

Then clean up, even if the run stopped early. Stop any services you started.

```bash
git worktree remove --force "$worktree" && git worktree prune
```

Check that `git status` in the scored repo matches what you noted in step 1,
that `core.hooksPath` matches `hooks-path-before`, and tell the user if either
changed. Finish by telling the user where the report is, and that it may quote
private code.
