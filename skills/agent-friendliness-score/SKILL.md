---
name: agent-friendliness-score
description: >-
  Grade a repo A to F in five categories on how safely AI coding agents can
  work in it, and end with the top three fixes. Measures whether the repo
  catches a plausible but wrong change by planting bugs in a throwaway clone,
  timing the tests and testing the docs with a fresh agent. Costs real time and
  agent usage. Work in progress.
disable-model-invocation: true
---

# Agent-friendliness score

> This skill is a work in progress.

Score one repo on one question: **if an agent makes a plausible but wrong
change, will the repo catch it?** Five categories, each graded A, B, C, D or F:
Verification, Feedback speed, Context, Consistency and Guardrails. There's no
overall score.

Every run is the full assessment. There are no lighter or deeper modes. Don't
run mutation testing or replay old pull requests. A mutation score the repo
already reports counts as evidence.

If the user named a package or path, score that. Otherwise score the whole repo.

Read these before scoring. They are part of this procedure:

- [references/checks.md](references/checks.md): how to run each measured check.
- [references/scoring.md](references/scoring.md): what each grade means, and
  when the report says "Not proven".

`scripts/sandbox.sh`, beside this file, manages the throwaway clone. Use it for
every action on the clone, by absolute path, from inside the scored repo:

```bash
bash /absolute/path/to/agent-friendliness-score/scripts/sandbox.sh restore
```

`bash scripts/sandbox.sh` would fail, or run the scored repo's own script. It's
called `sandbox` below. It keeps its paths in a state file. Before changing the
clone it checks that the recorded path has the shape setup creates, holds setup's
marker file, and is its own git toplevel with no remote. These checks catch
mistakes and a damaged state file, nothing stronger.

| Command | What it does |
|---------|--------------|
| `sandbox preflight [url...]` | Tests write and network access, and lists credential variable names. |
| `sandbox setup [scope]` | Creates the clone and save folder, and prints their paths. |
| `sandbox paths` | Prints the paths again. |
| `sandbox run -- <command>` | Runs one command in the clone, with credential variables unset. |
| `sandbox run -- bash -c 'npm ci && npm test'` | Runs several commands in the clone. **Shell operators outside the quotes, such as `&&`, run the next command in the scored repo, with credentials.** |
| `sandbox run --keep NAME -- <command>` | Keeps one credential variable, for private dependency installs only. |
| `sandbox settle [--reinstall]` | Commits everything in the clone as install output, and restores to that commit from then on. Refuses changes once settled, unless `--reinstall` follows a genuine second install. |
| `sandbox apply <patch>` | Applies a patch to the clone. |
| `sandbox capture <path>` | Saves the clone's changes as a patch in the save folder, then restores. |
| `sandbox restore` | Runs `git reset --hard HEAD` and `git clean -ffd` in the clone, with hooks off. |
| `sandbox find-report-folder [scope]` | Looks for `docs/` then `doc/`, and prints what it found. |
| `sandbox check-report-folder <folder>` | Checks the folder is inside the scored repo, with no `..` and no symlink leading out. |
| `sandbox finish [--complete [--report-to <folder>]]` | Removes the clone, checks it's gone, compares the scored repo with its state at setup, and then copies the report to the folder. |

## Rules for the whole run

- Never push, open a pull request, or change the scored repo's index, branches or
  config. All edits happen in the clone, which has no remote. The only write to the
  scored checkout is one report file, in the folder the user chose, written by
  `sandbox finish`. Never stage or commit it, and don't edit `.gitignore`.
- Don't commit seeded changes. Apply, test, restore.
- From CI, run only test, lint and typecheck steps. Never run release, deploy,
  publish, terraform or upload steps, even if a test step depends on them.
- Never copy `.env` files, credentials or other secret files into the clone or a
  report. `sandbox run` unsets variables whose names look like credentials. That
  goes by name, so it can miss some, and tests can still read files in the home
  directory. If tests need a credential, "When the baseline fails" in
  [references/checks.md](references/checks.md) says how to score it, unless the user
  gives a value that's safe for testing. Pass that with
  `sandbox run -- env NAME=value <command>`.
- If tests appear to reach production or shared services, stop and ask before
  running anything. Do the same if a run does something the plan didn't cover.
- If the search in step 1 flags a production or possibly shared service, that's a
  Guardrails finding, labelled static, so name it in the plan. A clearly local
  default, such as Postgres from the repo's compose file, passes with no question,
  and [references/scoring.md](references/scoring.md) covers a service with no default.
  With no default, the grade comes from
  [references/scoring.md](references/scoring.md), whatever the user answers. To run,
  never inherit a value: name the variable in the plan, and pass a safe value from the
  user with `sandbox run -- env NAME=value`, or clear it with `env -u NAME`. With no
  safe value, "When the baseline fails" in [references/checks.md](references/checks.md)
  says how to score it. If you can't tell whether a service is shared, ask rather than
  assume. Test isolation then has one of three results:
  - The user confirms nothing reaches production or shared services: it passes.
  - They're reached under the default the repo's config or docs set: it fails, even
    if the user supplies a safe target for this run.
  - The user can't say: it's not measured, with a ceiling. Don't run anything that
    could reach that service. Go on only with a safe target from the user, or if they
    explicitly accept the risk. Otherwise stop. A safe target still leaves test
    isolation not measured, because the repo's default remains unknown. Confirming
    the plan doesn't count as accepting this risk.

  If the run stops there, tell the user this finding is why, and run `sandbox finish`,
  without `--complete`, if `sandbox setup` has run.
- Never guess a result. A check that could not run is "not measured".
- The full report, `result.json`, patches and state stay in the save folder, which
  is always outside the scored repo. Paraphrase code and review comments where you
  can, because reports may quote private code. If you see a secret, don't repeat it.
  The planted fake credential is invented, never a real one. Name it in reports only
  by provider and file, never its value.
- Earlier reports can bias a run, because they can list which seeded bugs survived.
  Don't read a file named like `agent-friendliness-report-20261103T155624Z.md` in the
  repo, and don't count one as documentation or evidence. If one was read, by you or
  a subagent, say so in the report and `result.json`, the same way as a test that was
  read.
- Run `gh` from the scored repo, because the clone has no remote.

## 1. Read the repo

Read-only. Run `sandbox preflight`, adding the URL of any package registry this
stack needs. It exits 3 if the repo has no commits. Stop there and say why. Exit 1
means the run can't save its work, as described under Blocked access below.

If it lists an `active_run`, it shows when that run started and whether its state
file was used recently. That can't prove activity either way, and the run may be
live in another session. Ask the user before running `sandbox finish`, which would
remove its clone. If it lists a `leftover_clone`, an earlier run crashed, so offer
to delete it.

If `sandbox` reports a damaged state file, check no other session is using it, and
read preflight's output. Delete only a `leftover_clone` folder, named
`afs-sandbox.*` and holding `.afs-sandbox`. Never delete a path just because the
state file records it. Then remove the state file it names. If no `leftover_clone`
is listed, remove the state file only and leave any folder alone.

Find the stack, CI's test, lint and typecheck commands, how the repo documents its
setup, and any hooks the documented setup installs. Note the coverage tool and its
config: whether branch coverage is on, the threshold, whether CI fails on it, and
whether it applies overall or to changed code. Note the duplication tool the same
way, with the paths its config ignores. Note the type checker, whether it's strict
and whether CI fails on it. List the significant languages, as
[references/scoring.md](references/scoring.md) defines them, with the linter and
formatter CI runs for each, and whether each is established or custom. Note the
security scanners for each kind scoring.md lists, in CI and in documented hooks, and
whether a hook scans for secrets before commit or push. Read the docs and agent
instructions; step 4 builds the conventions list from them. Note whether the working
tree has uncommitted changes, because only the commit gets scored.

Look for services the tests may touch: Docker Compose files, database and queue
config, required environment variables, and HTTP calls without a stub library. This
search is the static evidence for test isolation in
[references/scoring.md](references/scoring.md).

Run `sandbox find-report-folder`, passing the package path if there is one, for the
plan's report location.

**Don't read test files until the seeded bugs are written** (step 4, item 1).
Until then, you may list their paths and read test config. To find service
connections in test files, search so that only connection details print, and drop
any credentials from what you repeat:

```bash
git grep -n -I -o -i -E '[a-z+]+://[^[:space:]"'\'']+|[a-z_]*(host|endpoint|database_url|dsn)[a-z_]*' -- <test paths>
```

## 2. Show the plan and confirm once

Show one plan and wait for one confirmation:

```text
Repo:         payments-api at 4f2a91c (uncommitted changes are not scored)
Commands:     bin/test, bin/lint, bin/typecheck, bundle exec brakeman, from CI.
              Skipped: deploy, publish-gem.
Install:      bundle install in a throwaway clone (runs install scripts)
Services:     Postgres from docker-compose.yml. No external URLs found.
Local data:   tests write to the local database payments_test
Credentials:  unset by name for test runs: AWS_SECRET_ACCESS_KEY, GH_TOKEN
              kept for install only: none
              tests can read these: ~/.aws, ~/.netrc
              This goes by name and path, so it can miss some.
Seeded:       10 bugs, plus 10 planted violations, including untested code, type
              errors, a fake credential, copied code and documented conventions
Agents:       3 fresh agents, one for the bugs and two for the docs check
Other:        npx jscpd for duplication; diff-cover for the changed-code coverage
              gate; read-only gh calls for CI history, review comments, merge
              rules and security settings; documented pre-commit hook with
              gitleaks, for violations the commands miss
Access:       save folder ok, temp ok, network ok, gh ok
Budget:       unknown until the first test run. Stops at 60 minutes.
Saved to:     ~/.agent-friendliness-score/payments-api-1a2b3c4d/ (full results)
Report copy:  where should the report go?
              1. docs/ (recommended)
              2. another folder in this repo
              3. home folder only
              Name: agent-friendliness-report-<timestamp>.md. It's untracked, and
              this skill won't stage or commit it. It can quote private code and
              describe where tests are weak, so check it before committing, more
              so on a public repo.
```

The report location is part of this one confirmation, not a separate prompt. Offer
the detected folder first, as recommended. If none was found, offer the repo root
first instead. Don't create a folder the user didn't choose. Check any other path
with `sandbox check-report-folder`, and ask again if it's refused.

Estimate time from CI history when you can, otherwise say "unknown". The budget is
the limit, and [references/checks.md](references/checks.md) says how to stay inside
it without asking again. If the user declines, stop. If they change something,
follow it.

**Blocked access.** Hosts that sandbox commands can block writes outside the
project, or the network. Say what preflight found, and ask the user to allow it
for this run. If the save folder stays blocked, stop, or ask for another folder
outside the repo and set `AFS_HOME=<folder>` on every `sandbox` command. If the
network stays blocked, installs and `gh` calls will fail, so the plan must list
those checks as not measured.

## 3. Set up

Run `sandbox setup`, passing the package path as the scope if there is one. It
prints the `sandbox` clone path, the commit, the `save_dir` and the `previous_run`.
Run `sandbox paths` if you need them again.

Install dependencies with `sandbox run`, the way the repo documents. If a private
dependency needs a credential, the plan can list `sandbox run --keep NAME`, for the
install only. Then run `sandbox settle`, even if install changed nothing or failed.
`apply` and `capture` refuse to run until you have. Note what the install needed, as
"Reproducible setup" in [references/checks.md](references/checks.md) says.

If install fails, follow "When the baseline fails" in
[references/checks.md](references/checks.md). Setup warns about submodules, Git
LFS and shallow history. A check that fails only because the clone has no
`origin`, such as a script using `origin/main`, is "not measured". Coverage gates
on changed code are the exception: [references/checks.md](references/checks.md)
evaluates them locally.

## 4. Run the measured checks

Run these in order, as [references/checks.md](references/checks.md) describes:

1. Have a fresh agent write the seeded bugs.
2. Run the baseline.
3. Time one test file and the relevant tests.
4. Run the seeded bugs.
5. Build the conventions list, with review history from `gh` if available.
6. Run the planted violations.
7. Run the two fresh-agent checks.
8. Run the consistency counts.
9. Read CI history, merge rules and security settings with `gh`, if available.

Run `sandbox restore` between changes to the clone. Don't use bare git commands
to restore. If there are no tests, skip steps 1 to 4 and carry on with the rest.
That's a measured result, an F for Verification.

## 5. Read the rest of the static evidence

Read any earlier report for this repo, and any tests you haven't read yet. Collect
the static evidence each category in [references/scoring.md](references/scoring.md)
asks for, including the counts of coverage exclusions, type-check escape hatches,
and security and duplication suppressions, and which check enforces each
tool-enforceable convention.

## 6. Grade

Apply [references/scoring.md](references/scoring.md). Label every piece of evidence
**static** or **measured**.

## 7. Choose the top three fixes

Each fix names the metric it can move, the current and target values, and what it
does to the grade. It claims a grade change, such as "Verification C to B", only if
it removes the last blocker for that grade. Otherwise it says how many it removes,
such as "removes 1 of 3 blockers for B". Rank by grade steps gained, then by fewest
blockers left, then Verification first. Make fixes about this repo and about classes
of mistake. "Add tests for these ten patches" only games the rerun, so don't suggest
it. A gap in this run's measurement isn't a fix either, so "install jscpd" or "move
to GitHub Actions" can't rank. List those gaps as ceilings in the evidence. A fix
must also pass the evidence filter in
[references/scoring.md](references/scoring.md), and, when a coverage, type-check,
lint-rule, security or duplication fix ranks, use the form scoring.md gives. Don't
apply any fix. This skill only reports.

## 8. Report, save and clean up

Show the report in this shape. The data here is made up.

````markdown
# Agent-friendliness: payments-api at 4f2a91c

```text
Verification    B  ███████████████░░░░░  7 of 10 seeded bugs caught
Feedback speed  B  ███████████████░░░░░  relevant tests in 3m 40s
Context         C  ██████████░░░░░░░░░░  5 of 6 answers correct  (ceiling: rules match not measured)
Consistency     B  ███████████████░░░░░  4.1% duplication  (low confidence)
Guardrails      B  ███████████████░░░░░  8 of 10 violations caught
```

This skill is a work in progress.

## Evidence
One section per category, headed with its grade and whether it's measured or
static only, such as "Context: C, measured (ceiling: rules match not measured)" or
"Consistency: C (static only)".
List each item with its label, static or measured, and each check marked not
measured or N/A with the reason.
Left out, with reason: merge rules, because classic protection returned 403.

## Seeded bugs
Who wrote them. A table of bug, risk category, caught or missed, and what caught
it. Name any bug "missed by relevant tests".

## Planted violations
A table of violation type, caught or missed, and what caught it, or why it left the
sample. On a rerun, the patches dropped and added. Name the fake credential only by
provider and file.

## Top three fixes
1. Add request tests for permission checks on refund endpoints. Can move the
   seeded catch rate from 70% to 90% (Verification B to A).

## Since the last run
Verification C to B. Guardrails B to C (rules changed since the last run). Other
grades unchanged. Seeded bugs: 5 of 7 reused caught, 2 of 3 new caught, 7 of 10
together. Commit 91bd03e to 4f2a91c.
````

The report opens with the grade card, one line per category: the name, the grade,
a bar of 20 cells with 5 filled per grade step (A 20, B 15, C 10, D 5, F 0), the
main evidence, and then any notes in brackets. The notes are a ceiling with what it
blocks, such as `(ceiling: rules match not measured)`, `(static only)` and
`(low confidence)`. Consistency is always low confidence. A static-only category
goes no higher than C, and its Evidence heading shows it with the grade, such as
`C (static only)`.

If [references/scoring.md](references/scoring.md) calls for a "Not proven" line,
put it straight under the card, before "This skill is a work in progress.", such as
"Not proven: Verification was not measured, so the repo's ability to catch a wrong
change is unknown."

If `previous_run` is set, compare against it. It's the newest run that finished.
Compare grades category by category, such as "Verification C to B", never a total.
Older runs saved points instead of letters. A measured category was out of 20, and
each 5 points is one grade step: 20 is A, 15 B, 10 C, 5 D and 0 F. A static-only
category was out of 10: 10 is C, 5 is D and 0 is F.

Rules change between versions of this skill. If the previous run's `version` differs
from this one, or it has none, mark each category whose rules changed "rules changed
since the last run", so a lower grade isn't read as a regression. If you can't tell
which changed, mark them all.

Save these in `save_dir`, alongside the patches, context files and conventions list
from step 4. They are what reruns compare against:

- `report.md`: the report above.
- `result.json`: commit, date, this skill's `version` from `plugin.json` in the
  plugin's `.claude-plugin/` or `.codex-plugin/` folder, two levels above this
  file, each category's grade as a letter and as points
  (A 20 to F 0), whether each category is measured, raw metrics, the merge state
  (required, not required or left out), push protection (on, off or left out), the
  test isolation result, setup findings, replaced questions, who wrote the bugs, the
  result for each patch, and the exact commands and searches used, so the next run
  can compare and repeat them.

Then run `sandbox finish --complete --report-to <folder>`, or leave out `--report-to`
if the user chose the home folder only. This compares the scored repo first and
copies the report afterwards, so the copy doesn't count as a change. If the run stops
early, run `sandbox finish`, which leaves the run out of later comparisons and copies
nothing. Stop any services you started first.

`finish` exits 4 if the scored repo changed since setup, and writes what changed
to `scored-repo-diff.txt`. Tell the user, since it may be their own work. If it
can't remove the clone it prints the path, so pass that on. If the copy fails, it
exits 5 and the report is still in `save_dir`. On exit 5, also read the `scored_repo`
line, because exit 5 hides the exit 4 for a changed repo.

Finish by giving the user the `report_copy` path, or the `save_dir` report if there's
no copy. Say the copy is untracked, that it can quote private code and describe where
tests are weak, and to check it before committing, more so on a public repo.
