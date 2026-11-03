# Scoring

All thresholds here are provisional.

## How to score a category

1. Each category scores 0, 5, 10, 15 or 20. Pick the highest level whose
   requirements are all met. There are no scores in between, because they would
   add noise between runs. Put partial progress in the evidence and raw metrics.
   In the tables, use a level's Measured clause when that category's measured
   check ran, and its Static clause when it didn't.
2. **Static evidence alone stops at 10.** Static means a file exists or a tool is
   configured. Measured means this run saw a result. Anything above 10 needs a
   measured result.
3. **Measured results win.** When a category's measured check ran, its result
   decides the level, even if the static evidence looks better.
4. **N/A.** If a requirement can't apply to this repo, such as performance
   budgets on a small CLI, mark it N/A and drop it from the level. The category
   stays out of 20, so its points move to what remains.
5. **Not measured.** If a category's measured check did not run, score it on
   static evidence, and it counts as 10 assessed points instead of 20. If some of
   its measured checks ran, score on those, and it stays at 20 assessed points.
   List the rest as not measured.

The total is the sum of scores out of the sum of assessed points. Below 100
assessed, show it as `60/80 assessed`.

## Verification

Can an agent prove a change is correct? "Catch rate" is the share of seeded bugs
caught.

| Score | Requires |
|-------|----------|
| 0 | No tests, or no seeded bugs caught. |
| 5 | Static: tests exist, but CI doesn't run them or a sample shows mostly weak assertions. Measured: catch rate below 40%, or nothing in the suite passes. |
| 10 | Static: CI runs the tests, coverage is reported, and a sample shows meaningful assertions. Measured: catch rate at least 40%. |
| 15 | Measured: catch rate at least 60%. |
| 20 | Measured: catch rate 85% or more, a missing permission check was caught where one applies, and a sample of tests shows no self-confirming pattern. |

Coverage is low-weight evidence, and a high number doesn't raise the level.

A mutation score the repo already reports, from a run in the last 30 days, is
supporting evidence. If it disagrees with the catch rate, report both, and the
catch rate decides. If seeded bugs did not run, it counts as the measured result,
at most 15: 80% or more scores 15, 60% to 79% scores 10, and below 60% scores 5.

## Feedback speed

How fast does an agent get a signal it can trust? "Relevant tests" is the time
for the tests relevant to a typical change.

| Score | Requires |
|-------|----------|
| 0 | No test command can be found or run. |
| 5 | Static: a test command exists but is undocumented. Measured: following the docs fails, or relevant tests take over 30 minutes. |
| 10 | Static: one documented command proves a change works, and running a single test file is documented. Measured: the command works, and relevant tests take under 30 minutes. |
| 15 | Measured: the documented command works on a clean checkout, relevant tests take under 5 minutes, and one test file runs in under 60 seconds. |
| 20 | Measured: relevant tests take under 60 seconds, one test file runs in under 15 seconds, no local flakes, flaky rate at or below 2%, CI under 15 minutes, and an agent can read logs and errors from the repo's documented tools. |

## Context

Can an agent find what it needs without flooding its context? "Answers" is the
share of repo questions answered correctly. "Rules match" is defined in
[checks.md](checks.md).

| Score | Requires |
|-------|----------|
| 0 | No usable README or agent instructions. Measured: answers below 20%. |
| 5 | Static: a README only, or agent instructions so long they don't work as an index. Measured: answers 20% to 49%. |
| 10 | Static: an `AGENTS.md` or `CLAUDE.md` of about 100 to 150 lines that points to deeper docs, rules that carry reasons, and at most 3 servers in committed MCP config. Measured: answers at least 50%. |
| 15 | Measured: answers at least 70%, and rules match at least 50%. |
| 20 | Measured: answers 85% or more, rules match at least 75%, and a median of 5 files or fewer opened per answer. |

Only committed MCP config counts. What's on a developer's machine isn't evidence
about the repo.

## Consistency

Is there one way to do each thing? This is the weakest category, because counts
can't judge intent. Mark it low confidence in every report. A "competing concern"
is one with two or more approaches and no preferred one named in the docs.

| Score | Requires |
|-------|----------|
| 0 | Measured: duplication over 15%, and at least two concerns have three or more approaches. |
| 5 | Static: no stated conventions. Measured: duplication 10% or more, or at least half the concerns are competing. |
| 10 | Static: conventions documented for most concerns, or a configured size or complexity limit. Measured: duplication under 10%, and at most two competing concerns. |
| 15 | Measured: duplication under 5%, at most one competing concern, and at most 3 non-generated files over about 1,000 lines. |
| 20 | Measured: duplication under 3%, no competing concerns, no file over about 1,000 lines in both hotspot lists, and CI enforces a size or complexity limit. |

If duplication is not measured, drop it and judge on the rest.

## Guardrails

Do mechanical checks enforce the conventions? "Catch rate" is the share of planted
violations caught.

| Score | Requires |
|-------|----------|
| 0 | No linter, formatter or other mechanical check. |
| 5 | Static: tools are configured, but CI doesn't run them. Measured: catch rate below 40%. |
| 10 | Static: CI runs a linter and formatter, plus a security scanner where the stack has one. Measured: catch rate at least 40%. |
| 15 | Measured: catch rate at least 60%, and CI runs a security scanner where the stack has one. |
| 20 | Measured: catch rate 85% or more, plus CI-enforced module boundary checks, performance budgets on key paths, and a rule or structural test for every convention corrected twice. Mark any of these N/A where it can't apply. |

## Verdict

Use the percentage of assessed points.

| Percent | Verdict |
|---------|---------|
| 85 to 100 | Basic harness is enough. |
| 65 to 84 | Agents can work here with review. |
| 40 to 64 | Expect wrong changes to get through. |
| Below 40 | Expect to hit the wall. |

Three rules can override the band:

- **Verification below 10** limits the verdict to "Expect wrong changes to get
  through", however high the total is.
- **Verification at 0** makes the verdict "Expect to hit the wall".
- **Verification not measured** replaces the verdict with "Not proven: the repo's
  ability to catch a wrong change was not measured", because that's the question
  this score exists to answer.
