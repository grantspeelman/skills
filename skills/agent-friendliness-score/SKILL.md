---
name: agent-friendliness-score
description: >-
  Score a repo out of 100 on how safely AI coding agents can work in it, and
  end with the top three fixes. Measures whether the repo catches a plausible
  but wrong change by planting bugs in a throwaway clone, timing the tests and
  testing the docs with a fresh agent. Costs real time and agent usage. Work in
  progress.
disable-model-invocation: true
---

# Agent-friendliness score

> This skill is a work in progress.

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
  the verdicts.

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
| `sandbox finish [--complete]` | Removes the clone, checks it's gone, and compares the scored repo with its state at setup. |

## Rules for the whole run

- Never push, open a pull request, or change the scored repo's working tree,
  index, branches or config. All edits happen in the clone, which has no remote.
- Don't commit seeded changes. Apply, test, restore.
- From CI, run only test, lint and typecheck steps. Never run release, deploy,
  publish, terraform or upload steps, even if a test step depends on them.
- Never copy `.env` files, credentials or other secret files into the clone or a
  report. `sandbox run` unsets variables whose names look like credentials. That
  goes by name, so it can miss some, and tests can still read files in the home
  directory. If tests need a credential, mark the affected checks "not measured"
  unless the user gives a value that's safe for testing. Pass that with
  `sandbox run -- env NAME=value <command>`.
- If tests appear to reach production or shared services, stop and ask before
  running anything. Do the same if a run does something the plan didn't cover.
- Never guess a result. A check that could not run is "not measured".
- Reports go only in the save folder, never in the scored repo. Paraphrase code
  and review comments where you can, because reports may quote private code. If
  you see a secret, don't repeat it.
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

Find the stack, CI's test, lint and typecheck commands, and how the repo documents
its setup. Note whether the working tree has uncommitted changes, because only the
commit gets scored.

Look for services the tests may touch: Docker Compose files, database and queue
config, required environment variables, and HTTP calls without a stub library.

**Don't read test files yet.** You may list their paths and read test config. To
find service connections in test files, search so that only connection details
print, and drop any credentials from what you repeat:

```bash
git grep -n -I -o -i -E '[a-z+]+://[^[:space:]"'\'']+|[a-z_]*(host|endpoint|database_url|dsn)[a-z_]*' -- <test paths>
```

## 2. Show the plan and confirm once

Show one plan and wait for one confirmation:

```text
Repo:         payments-api at 4f2a91c (uncommitted changes are not scored)
Commands:     bin/test, bin/lint, from CI. Skipped: deploy, publish-gem.
Install:      bundle install in a throwaway clone (runs install scripts)
Services:     Postgres from docker-compose.yml. No external URLs found.
Local data:   tests write to the local database payments_test
Credentials:  unset by name for test runs: AWS_SECRET_ACCESS_KEY, GH_TOKEN
              kept for install only: none
              tests can read these: ~/.aws, ~/.netrc
              This goes by name and path, so it can miss some.
Seeded:       10 bugs, plus 5 planted convention violations
Agents:       3 fresh agents, one for the bugs and two for the docs check
Other:        npx jscpd for duplication; read-only gh calls for CI history
Access:       save folder ok, temp ok, network ok, gh ok
Budget:       unknown until the first test run. Stops at 60 minutes.
Saved to:     ~/.agent-friendliness-score/payments-api-1a2b3c4d/ (may quote code)
```

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
`apply` and `capture` refuse to run until you have.

If install fails, follow "When the baseline fails" in
[references/checks.md](references/checks.md). Setup warns about submodules, Git
LFS and shallow history. A check that fails only because the clone has no
`origin`, such as a script using `origin/main`, is "not measured".

## 4. Run the measured checks

Run these in order, as [references/checks.md](references/checks.md) describes:

1. Have a fresh agent write the seeded bugs.
2. Run the baseline.
3. Time one test file and the relevant tests.
4. Run the seeded bugs.
5. Run the planted violations.
6. Run the two fresh-agent checks.
7. Run the consistency counts.
8. Read CI and review history with `gh`, if available.

Run `sandbox restore` between changes to the clone. Don't use bare git commands
to restore. If there are no tests, skip steps 1 to 4 and carry on with the rest.
That's a measured result, 0 out of 20 for Verification.

## 5. Read the static evidence

Now read the tests, and any earlier report for this repo. Collect the static
evidence each category in [references/scoring.md](references/scoring.md) asks for.

## 6. Score

Apply [references/scoring.md](references/scoring.md). Label every piece of evidence
**static** or **measured**.

## 7. Choose the top three fixes

Rank by points gained, and put Verification first on a tie. Each fix must name the
metric it moves, the current and target values, and roughly how many points it's
worth. Make fixes about this repo and about classes of mistake. "Add tests for
these ten patches" only games the rerun, so don't suggest it. A gap in this run's
measurement isn't a fix either, so "install jscpd" or "move to GitHub Actions"
can't rank. List those gaps as ceilings in the evidence. Don't apply any fix. This
skill only reports.

## 8. Report, save and clean up

Show the report in this shape. The data here is made up.

```markdown
# Agent-friendliness: payments-api at 4f2a91c

**70/100: Agents can work here with review.**
This skill is a work in progress.

| Category       | Score | Main evidence                                 |
|----------------|-------|-----------------------------------------------|
| Verification   | 15/20 | measured: 7 of 10 seeded bugs caught          |
| Feedback speed | 15/20 | measured: relevant tests in 3m 40s            |
| Context        | 10/20 (ceiling: rules match not measured) | measured: 5 of 6 answers correct |
| Consistency    | 15/20 | measured, low confidence: 4.1% duplication    |
| Guardrails     | 15/20 | measured: 4 of 5 planted violations caught    |

## Evidence
One section per category. List each item with its label, static or measured,
and each check marked not measured or N/A with the reason.

## Seeded bugs
Who wrote them. A table of bug, risk category, caught or missed, and what caught
it. Name any bug "missed by relevant tests".

## Top three fixes
1. Add request tests for permission checks on refund endpoints. Moves the
   seeded catch rate from 70% to 90% (Verification 15 to 20, +5 points).

## Since the last run
Total 60 to 70. Verification 10 to 15. Seeded bugs: 5 of 7 reused caught, 2 of 3
new caught, 7 of 10 together. Commit 91bd03e to 4f2a91c.
```

If a category is static only, list it separately with its score out of 10, and
show the total as measured points, such as `45/60 measured`.
[references/scoring.md](references/scoring.md) sets the headline and verdict.

If `previous_run` is set, compare against it. It's the newest run that finished.

Save these in `save_dir`, alongside the patches and context files from step 4:

- `report.md`: the report above.
- `result.json`: commit, date, scores, whether each category is measured, raw
  metrics, who wrote the bugs, the result for each patch, and the exact commands
  and searches used, so the next run can compare and repeat them.

Then run `sandbox finish --complete`. If the run stops early, run `sandbox finish`,
which leaves the run out of later comparisons. Stop any services you started first.

`finish` exits 4 if the scored repo changed since setup, and writes what changed
to `scored-repo-diff.txt`. Tell the user, since it may be their own work. If it
can't remove the clone it prints the path, so pass that on. Finish by telling the
user where the report is, and that it may quote private code.
