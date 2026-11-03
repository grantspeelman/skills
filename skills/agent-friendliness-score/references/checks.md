# Measured checks

Run these in order. `sandbox` means `bash <skill folder>/scripts/sandbox.sh`, with
the absolute path, as in [SKILL.md](../SKILL.md), run from the scored repo. Paths
like `seeded/` are inside `save_dir`. Save raw numbers for `result.json`.

"Commands" below means CI's test, lint and typecheck steps, or the documented
equivalents if there's no CI. Save them in `result.json`, and on a rerun use the
saved ones unless they no longer exist.

## Budget

The plan sets a time budget, 60 minutes by default. Never ask again to stay inside
it. An "unknown" estimate is fine, because the budget is the limit.

- Keep the last quarter of the budget for planted violations and fresh agents.
  Stop running seeded bugs when you reach it.
- **Suite over 5 minutes:** run each bug against its relevant tests first. Run the
  full commands only on bugs those tests miss, while budget remains.
- **First baseline over a third of the budget:** skip the second baseline, so local
  flakes are not measured, and use relevant tests only.
- **First baseline still running at three quarters of the budget:** stop it. Seeded
  bugs are not measured.
- A bug missed by its relevant tests, with no budget left for the full commands,
  counts as missed and is labelled "missed by relevant tests". A bug that never
  ran leaves the sample, and the report says so.

## Seeded bugs (Verification)

### Writing them

A fresh subagent writes the bugs, without seeing any tests, so its choices don't
fit the suite. First list:

- **Test paths**, from
  `sandbox run -- git ls-files | grep -E '(^|/)(tests?|specs?|__tests__|e2e|features)/|(^|/)test_|conftest\.py|[._]test\.|[._]spec\.|Tests?\.|\.Tests?/|\.bats$'`,
  plus anything else the repo uses.
- **Hotspots**, the production files most changed in the last 6 months, from
  `git log --since='6 months ago' --name-only --format= | sort | uniq -c | sort -rn`,
  without the test paths or earlier reports. If history is shallow, use the largest production files.

On a rerun, read only the earlier patches at this stage, not the earlier report.
Starting from the highest numbered, test patches with `sandbox apply` and
`sandbox restore`, and copy the first 7 that apply. Then ask for enough new bugs
to make 10. That's always at least 3 new.
Tests written against old patches would otherwise inflate the score.

Give the subagent this prompt, with no other findings from this run:

```text
Write <N> bugs for a test of this repository's safety checks. The code is in
<sandbox>. Read only production code and docs.

Don't open these test paths, and don't use git history to see them: <test paths>
Inline tests count as tests. In Rust, stop reading a file at #[cfg(test)], for
example with awk '/#\[cfg\(test\)\]/{exit}1' <file>. Ignore doctests, Python >>>
examples and in-source test blocks. Don't open files named
agent-friendliness-report-*, or see them through git history, because they are
earlier results of this test. If you read any of these anyway, say which file.

Choose sites from these often-changed files first: <hotspots>
Don't repeat these existing bugs: <reused patch paths, or none>

Cover these risk categories, at least one each where it applies: boundary or date
logic, missing permission check, wrong default, wrong error handling, dropped
validation. If one doesn't apply, use another mistake that fits the domain, such
as a wrong state transition or a rounding error. In a repo with little logic, use
what can go wrong there: a broken internal link, invalid config, a removed
required field.

Each bug must be a small change to production code, about 1 to 10 lines. It must
be a mistake a capable agent could plausibly make. It must change behaviour in a
way this repository's users could notice. It must compile. Leave test files alone,
and don't leave a comment or name that gives it away.

For each bug, edit the file in <sandbox>, then run:
  cd <scored repo> && <AFS_HOME=folder, if this run uses one> bash <absolute path to sandbox.sh> capture seeded/<NN>-<risk-category>.patch
Number from <next number>. That saves the patch and restores the code. Don't run
any tests. Finish with one line per bug: its number, what is wrong, who notices.
```

Replacements come from the same subagent, or a new one with this prompt if it can't
be resumed. Tell it only the patch number and that the patch was invalid, never
which tests ran or failed. Delete the replaced patch.

**No subagent on this host?** Show the user the prompt and ask them to run it in a
new session. If they would rather not, write the bugs yourself with the same rules.
The report and `result.json` must then say this session wrote them, and whether it
had read any tests or earlier reports by then. Do the same if the subagent read a
test or an earlier report.

### Running them

**Baseline.** Run the commands twice on the clean clone with `sandbox run`, using
`bash -c` to run more than one. Record failures from each run. A test that fails in only one is a local flake. Tests that
fail in either can't count as catching a bug.

**Each bug.** Run `sandbox apply seeded/<patch>`, then the commands, then
`sandbox restore`.

A bug is **caught** when a check fails in a way the baseline didn't, because of the
wrong behaviour. Record which check caught it. A type checker rejecting the wrong
behaviour is a catch.

- These don't count as catches: gates that fail on any patch, such as
  `git diff --exit-code` or a coverage threshold any change trips, and style-only
  failures, such as a lint error on an unused variable.
- A bug is **invalid** and gets replaced if it has a syntax error or an undefined
  name, if it trips only those gates, or if it turns out not to change behaviour.
- If a single test is the only new failure, run `sandbox restore` and rerun that
  test. If it fails without the patch too, it's a flake and doesn't count.

The catch rate covers all bugs in the sample together, reused and new. Report the
sample size with it, and on a rerun report the reused and new rates separately.
Fewer than 5 valid bugs that ran means seeded bugs are "not measured".

### When the baseline fails

- **Tests fail after following the repo's documented setup:** score it. Compare
  seeded runs against the baseline's failures. A suite where nothing passes catches
  nothing, so Verification is 0.
- **Setup needs something the docs don't mention:** that's a measured Feedback speed
  failure. Mark seeded bugs "not measured".
- **The docs are right and this machine lacks it,** such as a toolchain or a secret
  you can't copy: mark the affected checks "not measured", and say what was missing.
  The same goes for a hook installer refusing because this machine sets a global
  `core.hooksPath`.

## Timings (Feedback speed)

- **Full run:** the second baseline, so caches don't distort it, or the first if the
  second was skipped. Record install time separately.
- **One test file:** time a typical file, using the documented way if there is one.
- **Relevant tests:** take a production file from the hotspots and time the tests
  covering it. If the repo can't run only those, this time is the full run.
- **Local flakes:** tests that differed across the two baselines.

With `gh` and GitHub Actions, run this from the scored repo:

```bash
gh run list --workflow <main workflow> --branch <default branch> --limit 50 \
  --json conclusion,attempt,startedAt,updatedAt
```

CI time is the median duration of successful runs. Treat the share of runs with
`attempt` above 1 as the flaky rate. Without `gh`, or on another CI system, both
are optional and left out, as [scoring.md](scoring.md) explains.

## Planted violations (Guardrails)

Plant 5 violations, picking from these where they apply:

- a formatting break
- a breach of a configured lint rule
- a breach of a convention the repo states in its docs or agent instructions
- a call across a module boundary the repo says is off limits
- an obvious security flaw, such as unsanitised input in a query
- a fake credential in a real provider's format, invented for this run

For each, edit the clone, run `sandbox capture violations/<NN>-<type>.patch`, then
apply it, run the commands as CI runs them, and restore. If a scanner reads staged
files, staging in the clone is fine. On a rerun, reuse the earlier patches that
still apply, and top up to 5.

A violation counts as caught only if CI runs that check, or the documented setup
installs a hook that does. Fewer than 3 applicable violations means this check is
"not measured".

## Fresh-agent checks (Context)

Each needs an agent that hasn't seen this run. Start each in a fresh-context
subagent, pointed at the clean clone, and don't pass your findings.

No subagent on this host? Show the user the prompt and the clone path, and ask them
to run it in a new session and paste the answer back. If they would rather not,
mark the check "not measured". Never answer these prompts yourself, because you've
already read the repo.

`sandbox settle` removes committed `agent-friendliness-report-*` files from the clone,
but git history can still show them. If an agent says it read one, disclose it the
same way as a test that was read.

**Repo questions.** Write 6 questions an agent starting a task here would need
answered, with an answer key you checked against the code. For example: which
command proves a change to a given area works, where a given rule is enforced,
which module owns a given concern, what a new endpoint must do. Save both in
`context/questions.md`. On a rerun, reuse them, updating the key if the code
changed. Give the agent only this:

```text
Answer these questions about the repository at <sandbox>, using only what is in
that repository. Don't use the web. Don't run the tests. Don't open files named
agent-friendliness-report-*, or see them through git history. If you read one
anyway, say which file. If the repository doesn't answer a question, say so rather
than guessing. For each answer, list the files you opened.

<questions>
```

Score correct answers against the key, and record how many files each one took.

**Business rules from tests.** Give the agent only this:

```text
Read only the test files in the repository at <sandbox>. Don't open production code
or docs. Don't open files named agent-friendliness-report-*, or see them through git
history. If you read one anyway, say which file. Write down the business rules these
tests imply, one per line, with the test file each rule came from.
```

Compare the list with the docs, leaving out earlier reports, plus GitHub issues if `gh` can reach them. Rules
match is the share of written rules the docs confirm. List documented rules no test
implies, since these are gaps for the top fixes. If the repo has no tests, this
check is N/A.

## Consistency counts

This is the weakest measure. A count can't tell an unfinished migration from a
deliberate choice, so label it low confidence.

- **Duplication:** run `jscpd` or the stack's own tool if the plan listed it,
  excluding generated and vendored code. If none can run, mark it "not measured".
- **Competing patterns:** choose at least 4 concerns that apply, such as error
  handling, validation, data access, HTTP calls, config, logging, auth checks or
  state. Count the distinct approaches with repeatable searches, and check whether
  the docs name a preferred one. Save the search commands, and reuse them on a rerun.
- **Hotspots:** the hotspot list above, plus the 10 largest non-generated files.
  Note files on both lists. With shallow history, this is "not measured".

## Review history (Guardrails, optional)

"Corrected twice" counts only if `gh` can read review comments. Run from the scored
repo:

```bash
gh api "repos/{owner}/{repo}/pulls/comments?per_page=100&sort=created&direction=desc"
```

Find conventions corrected at least twice, then check whether a lint rule or
structural test now enforces each one. Paraphrase. If review history can't be read,
this item is optional and left out, as [scoring.md](scoring.md) explains.
