# Measured checks

Run these in the worktree, in this order. Save raw numbers for `result.json`.

## Budget

The plan sets a time budget, 60 minutes by default. Don't ask again to stay
inside it. If the full suite takes over 5 minutes, run each seeded bug against
its relevant tests first, and run the full suite only on bugs those tests miss
while budget remains. If budget runs out, the bugs that didn't run leave the
sample. Say so in the report.

## Seeded bugs (Verification)

**Write them before reading any test.** Use the production code and docs only,
and save every patch to `$save_dir/seeded/` before the baseline runs.

Write 10 bugs across these risk categories, at least one each where it applies:

- boundary or date logic
- missing permission check
- wrong default
- wrong error handling
- dropped validation

If a category doesn't apply, use another mistake that fits the domain, such as a
wrong state transition or a rounding error. In a repo with little logic, seed
what can go wrong there: a broken internal link, invalid config, a removed
required field.

Each bug must:

- be a small change to production code, about 1 to 10 lines
- be a mistake a capable agent could plausibly make, in code that matters to
  this repo's users
- change behaviour, so a user could notice the difference
- leave test files alone, with no comment or name that gives it away

On a rerun, reuse earlier patches from the newest save folder if they pass
`git apply --check`, then top up to 10. Always write at least 3 new bugs, even if
that takes the sample above 10, because tests written against old patches would
otherwise inflate the score. Report reused and new catch rates separately.

**Baseline.** Run the commands CI runs, twice, on the clean worktree. Record the
failures from each. A test that fails in only one run is flaky. Tests that fail
in either run can't count as catching a bug.

**Run each bug.** Apply the patch, run the commands, record the result, restore.

- A bug counts as caught when a check fails in a way the baseline didn't, because
  of the changed behaviour. Record which check caught it.
- If a single test is the only new failure, restore the worktree and rerun that
  test. If it also fails without the patch, it's flaky and doesn't count.
- A bug that doesn't compile doesn't count. Replace it without reading test
  contents. Do the same for a failure caused only by the patch's style, such as
  a lint error on an unused variable.
- If you find a bug didn't change behaviour after all, replace it too.

Report the sample size beside the catch rate, such as "7 of 10". Fewer than 5
valid bugs that ran means seeded bugs are "not measured".

**When the baseline fails.** Work out why:

- Tests fail after following the repo's documented setup: score it. Compare
  seeded runs against the baseline's failures. If nothing passes, seeded bugs
  can't be caught, so Verification is at most 5.
- Setup needs something the docs don't mention: score it, as a Feedback speed
  failure, and mark seeded bugs "not measured".
- The docs are right and this machine lacks it, such as a missing toolchain or a
  secret you can't copy: mark the affected checks "not measured", and say what
  was missing.

## Timings (Feedback speed)

- **Full run:** the second baseline, so caches don't distort it. Record install
  time separately.
- **One test file:** time a typical file, using the documented way if there is
  one.
- **Relevant tests:** choose a recently changed production file from `git log`
  and time the tests covering it. If the repo has no way to run only those,
  this time is the full run.
- **Local flakes:** tests that differed across the two baselines.

With `gh` and GitHub Actions, read the last 50 runs on the default branch:

```bash
gh run list --branch <default> --limit 50 \
  --json conclusion,attempt,startedAt,updatedAt,workflowName
```

CI time is the median duration of successful runs of the main workflow. Treat the
share of runs with `attempt` above 1 as the flaky rate. Without `gh`, or on
another CI system, mark both "not measured".

## Planted violations (Guardrails)

Plant 5 violations, one at a time, picking from these where they apply:

- a formatting break
- a breach of a configured lint rule
- a breach of a convention the repo states in its docs or agent instructions
- a call across a module boundary the repo says is off limits
- an obvious security flaw, such as unsanitised input in a query
- a fake credential in a real provider's format, invented for this run

Run the check commands as CI runs them. If a scanner reads staged files, staging
in the worktree is fine. A violation counts as caught only if CI runs that check,
or the documented setup installs a hook that does. Fewer than 3 applicable
violations means this check is "not measured".

## Fresh-agent checks (Context)

These need an agent that has not seen this run. Start each one in a fresh-context
subagent, pointed at the clean worktree, and don't pass your findings.

No subagent on this host? Show the user the prompt and the worktree path, and ask
them to run it in a new session and paste the answer back. If they would rather
not, mark the check "not measured". Never answer these prompts yourself, because
you've already read the repo.

**Repo questions.** Write 6 questions an agent starting a task here would need
answered, with an answer key you checked against the code. For example: which
command proves a change to a given area works, where a given rule is enforced,
which module owns a given concern, what a new endpoint must do. Give the agent
only this:

```text
Answer these questions about the repository at <worktree>, using only what is in
that repository. Don't use the web. Don't run the tests. If the repository
doesn't answer a question, say so rather than guessing. For each answer, list
the files you opened.

<questions>
```

Score correct answers against the key, and record how many files each one took.

**Business rules from tests.** Give the agent only this:

```text
Read only the test files in the repository at <worktree>. Don't open production
code or docs. Write down the business rules these tests imply, one per line, with
the test file each rule came from.
```

Compare the list with the docs, plus GitHub issues if `gh` can reach them. Rules
match is the share of written rules the docs confirm. List documented rules that
no test implies, since these are gaps for the top fixes. If the repo has no
tests, this check is N/A.

## Consistency counts

This is the weakest measure. A count can't tell an unfinished migration from a
deliberate choice, so label it low confidence.

- **Duplication:** run `jscpd` or the stack's own tool if the plan listed it,
  excluding generated and vendored code. If none can run, mark it "not measured".
- **Competing patterns:** choose at least 4 concerns that apply, such as error
  handling, validation, data access, HTTP calls, config, logging, auth checks or
  state. Count the distinct approaches with repeatable searches, and check
  whether the docs name a preferred one. Save the search commands, and reuse
  them on a rerun.
- **Hotspots:** list the 10 largest non-generated files and the 10 most changed
  in the last 6 months from `git log`. Note files on both lists.

## Review history (Guardrails, optional)

"Corrected twice" counts only if `gh` can read review comments. Read recent ones:

```bash
gh api "repos/{owner}/{repo}/pulls/comments?per_page=100"
```

Find conventions corrected at least twice, then check whether a lint rule or
structural test now enforces each one. Paraphrase. Otherwise this item is N/A.
