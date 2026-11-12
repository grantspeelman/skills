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
- **Planted violations:** run the commands likely to catch each one first, such as
  lint, format, typecheck or a hook. For the coverage types, that's the coverage
  command: a changed-code gate needs only the tests covering the touched file, an
  overall gate the full run. Run the full commands on any violation those miss,
  while budget remains. A violation that never ran leaves the sample.

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
Tests written against old patches would otherwise inflate the grade.

Give the subagent this prompt, with no other findings from this run:

```text
Write <N> bugs for a test of this repository's safety checks. The code is in
<sandbox>. Read only production code and docs.

Don't open these test paths, and don't use git history to see them: <test paths>
Inline tests count as tests. In Rust, stop reading a file at #[cfg(test)], for
example with awk '/#\[cfg\(test\)\]/{exit}1' <file>. Ignore doctests, Python >>>
examples and in-source test blocks. Don't open files named
like agent-friendliness-report-20261103T155624Z.md, or see them through git history, because they are
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
  `git diff --exit-code`, style-only failures, such as a lint error on an unused
  variable, and a warning from a check that still exits successfully.
- A coverage gate failing on a seeded bug isn't a catch, and doesn't make the bug
  invalid. Planted violations treat coverage differently; see there.
- A bug is **invalid** and gets replaced if it has a syntax error or an undefined
  name, if it trips only those gates, or if it turns out not to change behaviour.
- If a single test is the only new failure, run `sandbox restore` and rerun that
  test. If it fails without the patch too, it's a flake and doesn't count.

The catch rate covers all bugs in the sample together, reused and new. Report the
sample size with it, and on a rerun report the reused and new rates separately.
Fewer than 5 valid bugs that ran means seeded bugs are "not measured".

### When the baseline fails

- **Tests fail only because this run withheld a variable or credential:** that isn't a
  suite failure, so never grade it as Verification F. If nothing passes, seeded bugs
  and test timings are not measured. If some tests pass, score what ran against the
  baseline, and report which tests couldn't run. If the docs don't mention the
  variable, the Feedback speed failure below still applies.
- **`sandbox settle` printed `earlier_reports_removed_from_clone`, and only a link
  checker or similar fails on those files:** that comes from this run removing them, so it
  isn't the repo's failure. Leave that failure out of the grades.
- **Tests fail after following the repo's documented setup:** score it. Compare
  seeded runs against the baseline's failures. A suite where nothing passes catches
  nothing, so Verification is F.
- **Setup needs something the docs don't mention:** that's a measured Feedback speed
  failure. Mark seeded bugs "not measured".
- **The docs are right and this machine lacks it,** such as a toolchain: mark the
  affected checks "not measured", and say what was missing.
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

## Reproducible setup (Feedback speed)

Check these, each where it applies:

- **Lockfile:** one is committed. A repo without dependencies has no lockfile
  requirement, so this is N/A.
- **Tool versions:** pinned in a file such as `.tool-versions` or
  `rust-toolchain.toml`, or set by a dev container or Nix setup. Documented but
  unpinned doesn't count as pinned.
- **Setup command:** one documented command sets up the project.

During install, note any tool it needed that the repo doesn't pin, and save these for
`result.json`. Any such tool fails the requirement, even one this machine happened to
have. These everyday system tools don't need pinning: `git`, `make`, `curl`, a shell
and its standard utilities, a C compiler and Docker. Anything else does. Tools bundled
with a pinned tool are covered. Label the files static and the install notes measured.

## Planted violations (Guardrails)

Plant 10 violations. Required types go in wherever they apply:

- **untested branch:** about 1 to 10 lines of new production code with a branch no
  test covers, such as an added `if` path or a new function. Applies where the repo
  has tests and the stack has a branch-coverage tool, whether or not the repo
  configures it.
- **excluded untested branch:** the same, hidden behind a coverage exclusion, such as
  `# pragma: no cover` or `/* istanbul ignore next */`. Applies like the untested
  branch, where the tool has an exclusion mechanism.
- **type error:** a call with an argument of the wrong type, or a missing or
  misspelled field, in production code. Applies where the stack has a type checker,
  whether or not the repo configures it.
- **suppressed type error:** the same, hidden behind a suppression, such as
  `@ts-expect-error`, `# type: ignore[<code>]` or a cast through `any`: `any(x).(T)`
  in Go, `(T)(Object) x` in Java, `(T)(object) x` or `dynamic` in C#. Use the most
  permissive form the repo's own rules accept, such as `@ts-expect-error` with a
  description, because a rule an agent can satisfy without fixing the type doesn't
  count. Applies like the type error, where the language can hide a type error, so
  not Rust.

Write each required type so only the check it targets can fail:

- The coverage types pass lint, formatting, type checks and the existing tests. Only
  a check on coverage or the exclusion may fail.
- The type error passes lint and formatting, apart from lint rules on types. A type
  check or test failing on it is a catch, not a reason to replace it.
- The suppressed type error passes everything, the type checker and tests included.
  Only a check on the suppression may fail. Pick a site where the wrong type doesn't
  break the existing tests, such as a path they don't reach, or a mismatch that
  doesn't crash. If a test fails, replace the patch.

Where the run produces a coverage report, confirm from it that the branch really is
uncovered, and that the tool honours the exclusion form used. Where the repo
configures a type checker, confirm it reports the type error, and passes once the
suppression is added. If not, replace the patch.

Fill the rest from these, each where it applies. Include a breach of a documented
convention whenever the repo documents conventions:

- a breach of a convention the repo states in its docs or agent instructions
- a formatting break
- a breach of a configured lint rule
- a call across a module boundary the repo says is off limits
- an obvious security flaw, such as unsanitised input in a query
- a fake credential in a real provider's format, invented for this run
- a broken CI or config file, such as an invalid workflow or a config that fails its
  schema

Types may repeat to reach 10, each repeat using a different rule or site. Prefer
repeating documented convention, lint rule and security flaw. No type appears more
than twice. Fewer than 5 applicable types, or fewer than 5 violations that ran,
means this check is "not measured".

For each, edit the clone, run `sandbox capture violations/<NN>-<type>.patch`, then
apply it and run the commands as CI runs them, likely ones first as "Budget" says.
If the commands don't catch a violation and a documented hook runs a check for it,
run that hook in the clone with `sandbox run`, as the plan lists. If a scanner or
hook reads staged files, staging in the clone is fine. Then restore. On a rerun,
reuse the earlier patches that still apply, and top up to 10, keeping each required
type that applies.

A violation counts as caught only if CI runs that check, or the documented setup
installs a hook that does. A check that only prints a warning and still exits
successfully doesn't catch a violation. A broken CI or config file counts as caught
only if a check in the commands or a documented hook fails on it locally, because the
clone has no CI of its own. Nothing here should execute a deploy or release step.

**Coverage gates.** The clone has no `origin` and no CI services, so evaluate a gate
locally where that's deterministic. Run CI's coverage command, then apply the
configured target: an overall threshold as the tool runs it, or branch coverage of
the change against the settled baseline commit, such as
`diff-cover coverage.xml --compare-branch=<baseline sha> --fail-under=<target>` or
the tool's equivalent. Take the target from the repo's config, such as the patch
target in `codecov.yml` or a Sonar new-code condition, and label the result
"measured, evaluated locally against <config>". This is how a changed-code gate
avoids the no-`origin` rule in step 3 of [SKILL.md](../SKILL.md). A Codecov status
marked `informational` isn't a gate. If the target can't be reproduced, such as
Codecov `target: auto` or a gate set only on a Sonar server, and no gate that could
be evaluated caught it, the untested branch is not measured and leaves the sample.
List extra tools, such as diff-cover, on the plan's `Other:` line.

An untested branch counts as caught only if a coverage gate fails on it. Don't
enlarge the patch to trip an overall gate. If the gate already fails on the baseline,
it's missed, because a red gate protects nothing, unless it fails only because this
run withheld a variable or credential. Then it's not measured, as in "When the
baseline fails". An excluded untested branch counts as caught only if something fails
because of the exclusion, such as a lint rule banning new exclusion comments or a
check on changes to coverage config. A coverage gate that passes because the code is
excluded misses it.

**Type errors.** A type error counts as caught if a check in the commands, or a
documented hook, fails on it. Record which: a type checker, the compiler, a lint rule
on types, or a test failing at runtime. A test failure is a genuine catch, but the
report says the tests caught it, not a type checker. A coverage gate failing on a
type error isn't a catch. A type checker that already fails on the baseline catches
nothing, like a red coverage gate, unless it uses a baseline file of known errors and
fails only on new ones. A suppressed type error counts as caught only if something
fails because of the suppression, such as `@typescript-eslint/ban-ts-comment`,
`no-explicit-any`, golangci-lint `forcetypeassert` or a Semgrep rule. A type checker
that passes because of the suppression misses it.

## Fresh-agent checks (Context)

Each needs an agent that hasn't seen this run. Start each in a fresh-context
subagent, pointed at the clean clone, and don't pass your findings.

No subagent on this host? Show the user the prompt and the clone path, and ask them
to run it in a new session and paste the answer back. If they would rather not,
mark the check "not measured". Never answer these prompts yourself, because you've
already read the repo.

`sandbox settle` removes committed reports, named like
`agent-friendliness-report-20261103T155624Z.md`, from the clone,
but git history can still show them. If an agent says it read one, disclose it the
same way as a test that was read.

**Repo questions.** Write 6 questions an agent starting a task here would need
answered, with an answer key you checked against the code. For example: which
command proves a change to a given area works, where a given rule is enforced,
which module owns a given concern, what a new endpoint must do.

Where it applies, the six must include one each on: what an agent must not do without
asking, which environment variables and services are needed to run the project, what
kind of test a change to a named area needs and where it goes, and why a notable
design choice was made. For the last, choose the design choice with the most effect
on a typical change, before checking whether the docs explain it.

If nothing in the repo answers a question, code included, keep it and say so in the
key. An agent saying "the repo doesn't say" is honest but isn't correct, because this
measures what the repo tells an agent. A correct answer read from the code counts,
such as a list of environment variables.

Save both in `context/questions.md`. On a rerun, reuse them, updating the key if the
code changed. If an older set lacks any of those four, replace the questions closest
in topic to the missing ones, never choosing by which questions failed. The report
names the questions removed and the ones added. Give the agent only this:

```text
Answer these questions about the repository at <sandbox>, using only what is in
that repository. Don't use the web. Don't run the tests. Don't open files named
like agent-friendliness-report-20261103T155624Z.md, or see them through git history. If you read one
anyway, say which file. If the repository doesn't answer a question, say so rather
than guessing. For each answer, list the files you opened.

<questions>
```

Score correct answers against the key, and record how many files each one took.

**Business rules from tests.** Give the agent only this:

```text
Read only the test files in the repository at <sandbox>. Don't open production code
or docs. Don't open files named like agent-friendliness-report-20261103T155624Z.md, or see them through git
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

## Merge rules (Guardrails, optional)

A check that runs in CI but isn't required can still be merged. Run from the scored
repo:

```bash
gh api repos/{owner}/{repo}/rules/branches/<default branch>
gh api repos/{owner}/{repo}/branches/<default branch>/protection
```

The first returns rulesets, so look for `required_status_checks`. The second is
classic protection, which usually needs admin. Together they give the checks that
are **required to merge**.

Compare these with the CI checks that caught planted violations and seeded bugs,
using the workflow files. The planted violations decide the grade. Report any
seeded-bug check that isn't required as evidence.

Work this out in order, and stop at the first that applies:

1. **The host isn't GitHub:** this item is left out, as [scoring.md](scoring.md)
   explains.
2. **Every planted-violation catch came from a hook:** the requirement isn't met, even
   if the settings can't be read. Report it as "only hooks caught these", never as
   "unprotected".
3. **Otherwise,** leave hook-only catches out of the comparison, and give each CI
   check that caught a planted violation one of the states below. If any is not
   required, the requirement isn't met. If all are required, it's met. Otherwise this
   item is left out.

- **Required:** either response lists it. A check's name can differ from the job key,
  because of a `name:` override or a matrix suffix. It's also required if a required
  job depends on it through `needs` and fails when it fails, or if it runs inside a
  required external status, such as one `buildkite/pipeline` status covering every
  step.
- **Not required:** both responses can be read, and you can establish that no required
  check covers it.
- **Left out:** you can't establish the mapping, or one response can't be read and
  the other doesn't make it required.

Classic protection can be read if it returns its settings, or a 404 whose message
says the branch isn't protected. Any other 403 or 404 can't be read, and neither can
a failed rules call, so an empty rules response with unreadable classic protection
doesn't prove the branch is unprotected.

Label this static, because it reads settings. It doesn't make Guardrails measured by
itself. Also record whether reviews are required and whether a `CODEOWNERS` file
exists.
