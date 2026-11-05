# Scoring

## Scoring a category

A category scores 0, 5, 10, 15 or 20. There are no scores in between, because they
would add noise between runs. Put partial progress in the evidence and raw metrics.

A category is **measured** if any of its measured checks ran, or if you confirmed
the thing it measures doesn't exist. No tests is a measured 0 out of 20 for
Verification, and no checks at all is a measured 0 for Guardrails. Use a level's
Measured clause. Measured results decide the level, even when the static evidence
looks better.

A category is **static only** if none of its measured checks ran. Use the Static
clauses, which stop at 10. Static means a file exists or a tool is configured.

A committed report named like `agent-friendliness-report-20261103T155624Z.md` is a past result of this
skill. It never counts as documentation or evidence in any category. A repo's own
file with a similar name, such as `agent-friendliness-report-guide.md`, counts as
usual.

**Evidence filter.** Only count a piece of static evidence, or suggest a fix, if you
can answer "if this is missing, what goes wrong for an agent?". A license, code of
conduct, stale-issue bot or label automation has no clear answer, so it doesn't count.

To pick the level:

1. If level 0's condition holds, score 0.
2. Otherwise take the highest of 20, 15 and 10 whose requirements are all met.
3. If none is met, score 5. This covers any result that falls between levels.

Two kinds of missing requirement are treated differently:

- **N/A:** it can't apply to this repo, such as performance budgets on a small CLI.
  Drop it from the level. The category stays out of 20.
- **Not measured:** it applies, but the check couldn't run. It's never N/A, and it
  blocks any level that names it. Show what it blocks as a ceiling, such as
  `15/20 (ceiling: rules match not measured)`. A ceiling is a gap in this run, so it
  never counts as a top fix.

**Optional items.** Flaky rate, CI time, review history and merge rules live on a
hosting service, so they say more about access or the CI provider than about the
repo. When they can't be reached, leave them out, name each with the reason in the
report, and don't show a ceiling. When they can, they count like any other
requirement. A repo on another CI system can still reach level 20.
[checks.md](checks.md) sets the order for merge rules, including when only hooks
caught violations.

## Verification

Can an agent prove a change is correct? "Catch rate" is the share of seeded bugs
caught.

A test is **self-confirming** if it would still pass with the behaviour wrong: it
has no assertion, checks only a value it set itself or a mock it set up, or works
out its expected value by copying the implementation. Sample 20 tests across the
hotspots.

| Score | Static | Measured |
|-------|--------|----------|
| 0 | No tests. | No tests, no seeded bugs caught, or a suite where nothing passes. |
| 5 | Tests exist, but CI doesn't run them, or most of the sample is self-confirming. | Catch rate above 0% and below 40%. |
| 10 | CI runs the tests, coverage is reported, and at most 5 of the sample are self-confirming. | Catch rate at least 40%. |
| 15 | | Catch rate at least 60%, from at least 8 valid bugs. |
| 20 | | Catch rate at least 85%, from at least 8 valid bugs, a missing permission check caught where one applies, and at most 1 of the sample self-confirming. |

Coverage is low-weight evidence, and a high number doesn't raise the level.

A mutation score the repo already reports, from a run in the last 30 days, is
supporting evidence. If it disagrees with the catch rate, report both, and the
catch rate decides. If seeded bugs did not run, it counts as the measured result:
at least 80% scores 15, at least 60% scores 10, and anything lower scores 5.

## Feedback speed

How fast does an agent get a signal it can trust? "Relevant tests" is the time for
the tests relevant to a typical change. "Reproducible setup" means dependencies are
locked, tool versions are pinned, not just documented (a dev container or Nix setup
also counts), and one documented command sets up the project, each where it applies.

| Score | Static | Measured |
|-------|--------|----------|
| 0 | No test command can be found. | No test command can be found or run. |
| 5 | A test command exists but is undocumented. | Following the docs fails, or relevant tests take 30 minutes or more. |
| 10 | One documented command proves a change works, and running a single test file is documented. | The documented command works, and relevant tests take under 30 minutes. |
| 15 | | The documented command works on a clean checkout, relevant tests take under 5 minutes, one test file runs in under 60 seconds, and the repo has a reproducible setup. |
| 20 | | Relevant tests take under 60 seconds, one test file runs in under 15 seconds, no local flakes, flaky rate at most 2% and CI under 15 minutes (both optional), an agent can read logs and errors from the repo's documented tools, and the repo has a reproducible setup. |

## Context

Can an agent find what it needs without flooding its context? "Answers" is the share
of repo questions answered correctly. "Rules match" is defined in
[checks.md](checks.md).

| Score | Static | Measured |
|-------|--------|----------|
| 0 | No usable README or agent instructions. | Answers below 20%. |
| 5 | A README only, or agent instructions so long they don't work as an index. | Answers at least 20%. |
| 10 | An `AGENTS.md` or `CLAUDE.md` of at most about 150 lines that points to deeper docs, rules that carry reasons, and at most 3 servers in committed MCP config. | Answers at least 50%. |
| 15 | | Answers at least 70%, and rules match at least 50%. |
| 20 | | Answers at least 85%, rules match at least 75%, and a median of 5 files or fewer opened per answer. |

Only committed MCP config counts. What's on a developer's machine isn't evidence
about the repo.

Record these as static evidence. They don't change the level: committed agent
settings, hooks, skills and editor rules, such as `.claude/settings.json`,
`.cursor/rules/` or `.github/copilot-instructions.md`, instruction files in
subdirectories, and whether a second agent tool would pick up the same instructions.
A `CLAUDE.md` with no `AGENTS.md` leaves Codex without them. When scoring a package,
check for instruction files that apply to that package's path.

## Consistency

Is there one way to do each thing? This is the weakest category, because counts can't
judge intent. Mark it low confidence in every report. A **competing concern** has two
or more approaches and no preferred one named in the docs.

| Score | Static | Measured |
|-------|--------|----------|
| 0 | | Duplication over 15%, and at least two concerns have three or more approaches. |
| 5 | No stated conventions. | Duplication 10% or more, or more than two competing concerns. |
| 10 | Conventions documented for most concerns, or a configured size or complexity limit. | Duplication under 10% or not measured, and at most two competing concerns. |
| 15 | | Duplication under 5%, at most one competing concern, and at most 3 non-generated files over about 1,000 lines. |
| 20 | | Duplication under 3%, no competing concerns, no file over about 1,000 lines on both hotspot lists, and CI enforces a size or complexity limit. |

Without a duplication tool, this category stops at 10. Show it as a ceiling,
`10/20 (ceiling: duplication not measured)`.

## Guardrails

Do mechanical checks enforce the conventions? "Catch rate" is the share of planted
violations caught. "Required to merge" is defined in [checks.md](checks.md). "Test
isolation" means that under the default the repo's config or docs set, tests use only
local or test services, not production or shared ones. It's static evidence from the
service search in step 1 of [SKILL.md](../SKILL.md), and "Rules for the whole run"
there gives the result when that search flags a service. If the tests use no
services, it's N/A.

| Score | Static | Measured |
|-------|--------|----------|
| 0 | No linter, formatter or other mechanical check. | No such checks, or no violations caught. |
| 5 | Tools are configured, but CI doesn't run them. | Catch rate above 0% and below 40%. |
| 10 | CI runs a linter and formatter, plus a security scanner where the stack has one. | Catch rate at least 40%. |
| 15 | | Catch rate at least 60%, CI runs a security scanner where the stack has one, test isolation where it applies, and the checks that caught violations are required to merge (optional). |
| 20 | | Catch rate at least 85%, plus CI-enforced module boundary checks and performance budgets on key paths, each where it applies, test isolation where it applies, a rule or structural test for every convention corrected twice (optional), and the checks that caught violations are required to merge (optional). |

Whether reviews are required and whether a `CODEOWNERS` file exists are evidence only,
and don't change the level. `CODEOWNERS` counts as evidence of review only if review
is actually required.

## Score and verdict

Static-only categories never count towards the score. Show them separately, out of
10. A failed check can't raise the score, because it takes the category out of the
sum rather than leaving its static points in.

The **score** is the measured categories' points as a percentage of their available
points, rounded down. With all five measured, that's the total out of 100. Work out
the headline in this order, and stop at the first that applies:

1. **Not proven.** Show the points, such as `30/40 measured`, with no band.
   - If Verification isn't measured, the verdict is "Not proven: the repo's ability
     to catch a wrong change was not measured".
   - If Verification is measured but fewer than 3 categories are, the verdict is
     "Not proven: too few categories were measured for a verdict".
2. **Verification cap.** Verification at 0 caps the score at 39. Verification at 5
   caps it at 64. Show the uncapped figure too, such as
   `64/100 (80 before the Verification cap)`.
3. **Band.** Read the verdict from the score, after any cap.

| Score | Verdict |
|-------|---------|
| At least 85 | Basic harness is enough. |
| At least 65 | Agents can work here with review. |
| At least 40 | Expect wrong changes to get through. |
| Below 40 | Expect to hit the wall. |
