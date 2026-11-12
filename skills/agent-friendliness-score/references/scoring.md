# Scoring

## Grading a category

A category gets a grade: A, B, C, D or F. Each step is worth 5 points, so A is 20,
B 15, C 10, D 5 and F 0. `result.json` stores both. There are no grades in between,
because they would add noise between runs. Put partial progress in the evidence and
raw metrics. There's no overall score.

A category is **measured** if any of its measured checks ran, or if you confirmed
the thing it measures doesn't exist. No tests is a measured F for Verification,
and no checks at all is a measured F for Guardrails. Use a grade's Measured clause.
Measured results decide the grade, even when the static evidence looks better.

A category is **static only** if none of its measured checks ran. Use the Static
clauses, which stop at C. Static means a file exists or a tool is configured. Step 8
of [SKILL.md](../SKILL.md) says how the report shows a static-only grade.

A committed report named like `agent-friendliness-report-20261103T155624Z.md` is a past result of this
skill. It never counts as documentation or evidence in any category. A repo's own
file with a similar name, such as `agent-friendliness-report-guide.md`, counts as
usual.

**Evidence filter.** Only count a piece of static evidence, or suggest a fix, if you
can answer "if this is missing, what goes wrong for an agent?". A license, code of
conduct, stale-issue bot or label automation has no clear answer, so it doesn't count.

To pick the grade:

1. If F's condition holds, grade F.
2. Otherwise take the highest of A, B and C whose requirements are all met.
3. If none is met, grade D. This covers any result that falls between grades.

Two kinds of missing requirement are treated differently:

- **N/A:** it can't apply to this repo, such as performance budgets on a small CLI.
  Drop it from the grade. The category can still reach A.
- **Not measured:** it applies, but the check couldn't run. It's never N/A, and it
  blocks any grade that names it. Show what it blocks as a ceiling, such as
  `C (ceiling: rules match not measured)`. A ceiling is a gap in this run, so it
  never counts as a top fix.

**Optional items.** Flaky rate, CI time, merge rules and GitHub security settings
live on a hosting service, so they say more about access or the CI provider than about
the repo. When they can't be reached, leave them out, name each with the reason in the
report, and don't show a ceiling. When they can, they count like any other
requirement. A repo on another CI system can still reach A. [checks.md](checks.md)
sets the order for merge rules, including when only hooks caught violations.

## Verification

Can an agent prove a change is correct? "Catch rate" is the share of seeded bugs
caught.

A test is **self-confirming** if it would still pass with the behaviour wrong: it
has no assertion, checks only a value it set itself or a mock it set up, or works
out its expected value by copying the implementation. Sample 20 tests across the
hotspots.

| Grade | Static | Measured |
|-------|--------|----------|
| F | No tests. | No tests, no seeded bugs caught, or a suite where nothing passes. |
| D | Tests exist, but CI doesn't run them, or most of the sample is self-confirming. | Catch rate above 0% and below 40%. |
| C | CI runs the tests, coverage is reported, and at most 5 of the sample are self-confirming. | Catch rate at least 40%. |
| B | | Catch rate at least 60%, from at least 8 valid bugs. |
| A | | Catch rate at least 85%, from at least 8 valid bugs, a missing permission check caught where one applies, and at most 1 of the sample self-confirming. |

Coverage is low-weight evidence, and a high number doesn't raise the grade.

A mutation score the repo already reports, from a run in the last 30 days, is
supporting evidence. If it disagrees with the catch rate, report both, and the
catch rate decides. If seeded bugs did not run, it counts as the measured result:
at least 80% is a B, at least 60% a C, and anything lower a D.

## Feedback speed

How fast does an agent get a signal it can trust? "Relevant tests" is the time for
the tests relevant to a typical change. "Reproducible setup" means dependencies are
locked, tool versions are pinned, not just documented (a dev container or Nix setup
also counts), and one documented command sets up the project, each where it applies.

| Grade | Static | Measured |
|-------|--------|----------|
| F | No test command can be found. | No test command can be found or run. |
| D | A test command exists but is undocumented. | Following the docs fails, or relevant tests take 30 minutes or more. |
| C | One documented command proves a change works, and running a single test file is documented. | The documented command works, and relevant tests take under 30 minutes. |
| B | | The documented command works on a clean checkout, relevant tests take under 5 minutes, one test file runs in under 60 seconds, and the repo has a reproducible setup. |
| A | | Relevant tests take under 60 seconds, one test file runs in under 15 seconds, no local flakes, flaky rate at most 2% and CI under 15 minutes (both optional), an agent can read logs and errors from the repo's documented tools, and the repo has a reproducible setup. |

## Context

Can an agent find what it needs without flooding its context? "Answers" is the share
of repo questions answered correctly. "Rules match" is defined in
[checks.md](checks.md).

| Grade | Static | Measured |
|-------|--------|----------|
| F | No usable README or agent instructions. | Answers below 20%. |
| D | A README only, or agent instructions so long they don't work as an index. | Answers at least 20%. |
| C | An `AGENTS.md` or `CLAUDE.md` of at most about 150 lines that points to deeper docs, rules that carry reasons, and at most 3 servers in committed MCP config. | Answers at least 50%. |
| B | | Answers at least 70%, and rules match at least 50%. |
| A | | Answers at least 85%, rules match at least 75%, and a median of 5 files or fewer opened per answer. |

Only committed MCP config counts. What's on a developer's machine isn't evidence
about the repo.

Record these as static evidence. They don't change the grade: committed agent
settings, hooks, skills and editor rules, such as `.claude/settings.json`,
`.cursor/rules/` or `.github/copilot-instructions.md`, instruction files in
subdirectories, and whether a second agent tool would pick up the same instructions.
A `CLAUDE.md` with no `AGENTS.md` leaves Codex without them. When scoring a package,
check for instruction files that apply to that package's path. Also record whether
the instructions or docs describe a testing approach, such as TDD, writing testable
code, where tests go and what kind of tests to write.

## Consistency

Is there one way to do each thing, and does the repo stop new copies? This is the
weakest category, because counts can't judge intent. Mark it low confidence in every
report. The duplication gate and the copied-code result are concrete checks, so the
evidence doesn't label them low confidence. A **competing concern** has two or more
approaches and no preferred one named in the docs.

A **duplication gate** is a duplication check that fails CI, on the whole codebase or
on changed code, such as jscpd with a threshold, PMD CPD, pylint `duplicate-code`,
golangci-lint `dupl`, flay, or SonarQube or Qlty duplication on new code. Both count
the same. A Sonar or Qlty result counts when CI fails on it, such as with
`sonar.qualitygate.wait=true`, or as a status, as for a coverage gate in Guardrails.
Gate requirements are N/A where no production language has a duplication tool.

The copied-code violation in [checks.md](checks.md) counts in the Guardrails catch
rate like any violation, and is the measured evidence for the duplication gate. A copy
caught in CI proves a gate exists. A gate that misses it still counts when the copy
stayed within its threshold, as with an overall percentage, and the miss only lowers
the catch rate. It doesn't count when the copy falls outside what it checks, such as
an ignored path, a language it doesn't cover, a job that doesn't run or a scan of
changed files only, because measured beats static. An overall percentage rarely
catches one copy, which is why the duplication fix below is a gate on changed code.

Record as static evidence the duplication tool, its threshold, whether CI fails on
it, and whether it applies overall or to changed code. Also record suppressions,
leaving out generated, vendored and test code: comments such as `jscpd:ignore-start`
blocks, `# pylint: disable=duplicate-code` or `//nolint:dupl`, per 1,000 lines of
production code; and separately, the production lines in paths the duplication
config ignores. Suppressions are **checked** when a new one fails a check unless it
gives a reason, or needs a required review, such as `CODEOWNERS` on the config with
reviews required, which also covers new ignored paths. Save the searches for reruns.

| Grade | Static | Measured |
|-------|--------|----------|
| F | | Duplication over 15%, and at least two concerns have three or more approaches. |
| D | No stated conventions. | Duplication 10% or more, or more than two competing concerns. |
| C | Conventions documented for most concerns, or a configured size or complexity limit. | Duplication under 10% or not measured, and at most two competing concerns. |
| B | | Duplication under 5%, at most one competing concern, at most 3 non-generated files over about 1,000 lines, and a duplication gate where it applies. |
| A | | Duplication under 3%, no competing concerns, no file over about 1,000 lines on both hotspot lists, CI enforces a size or complexity limit, and a duplication gate with its suppressions checked, where it applies. |

If the duplication count can't run, this category stops at C. Show it as a ceiling,
`C (ceiling: duplication not measured)`.

**Duplication fix.** When there's no duplication gate, or the copied code got past
it, suggest a gate on changed code that scans the whole tree, naming the tool for this
stack, such as "run jscpd on the whole tree in CI and fail on clones in changed
files" or "turn on golangci-lint `dupl` with `new-from-merge-base`". It moves the
copied-code catch, the Guardrails catch rate and the Consistency grade, such as
"Consistency C to B". When duplication suppressions aren't checked, name the check,
such as `CODEOWNERS` on `.jscpd.json` with reviews required, for "Consistency B to A".

## Guardrails

Do mechanical checks enforce the conventions? "Catch rate" is the share of planted
violations caught. "Required to merge" is defined in [checks.md](checks.md). "Test
isolation" means that under the default the repo's config or docs set, tests use only
local or test services, not production or shared ones. It's static evidence from the
service search in step 1 of [SKILL.md](../SKILL.md), and "Rules for the whole run"
there gives the result when that search flags a production or possibly shared
service. A clearly local default, such as Postgres from the repo's compose file,
passes with no question. With no default, such as a required `DATABASE_URL` with no
value set, it fails unless the docs direct users to a local or test service. If the
tests use no services, it's N/A.

A **coverage gate** is a branch-coverage threshold that fails CI, on the whole
codebase or on changed code, such as diff-cover, a Codecov patch target or a
SonarQube new-code condition. Both count the same. Codecov and Sonar post a status
rather than failing a job, so a failing status counts unless it's marked
`informational`. Codecov's `target: auto` has no fixed number, so it can't meet 95%.
A line-only threshold or a report that never fails isn't a gate. The untested branch
(not the excluded one) caught in CI proves a gate exists. A gate that misses it still
counts when the change met its target, as with an overall gate or a changed-code
target the change was above, and the miss only lowers the catch rate. It doesn't
count when the change falls outside what it checks, such as an ignored path, a
language it doesn't cover or a job that doesn't run, because measured beats static.
An overall gate below 100% rarely catches a small untested branch, which is why the
coverage fix below is a gate on changed code. Gate requirements are N/A where the
stack has no branch-coverage tool, or the repo has no tests, which Verification
already covers. Not configuring the stack's tool doesn't make them N/A.

Record as static evidence the coverage tool, whether branch coverage is on, the
threshold, whether CI fails on it, and whether it applies overall or to changed code.
Also record exclusions, leaving out generated, vendored and test code: exclusion
comments, such as `# pragma: no cover` or `istanbul ignore`, per 1,000 lines of
production code (counting lines in ignored paths too); and separately, the
production lines in paths the coverage config ignores. Save the searches for reruns.
Exclusions usually point to code that's hard to test, and they're the quickest way
for an agent to pass a gate.

A **type checker** counts when CI runs it and fails the build on an error, such as
`tsc --noEmit`, mypy, pyright, Sorbet or PHPStan. A TypeScript build through esbuild,
swc, Vite or Babel, or tests through Vitest or ts-jest with `isolatedModules`, don't
type-check, so they don't count. It's **strict** when the stack's strict setting is
the default for production code, such as TypeScript `strict`, mypy `--strict` or
pyright `strict` mode, and files or modules opted out or checked loosely hold under
10% of production lines. For Sorbet the bar is `typed: strict`, by share of lines.
Compiled languages with static types, such as Go, Rust, Java or C#, meet both through
their compiler when CI builds the code.

Type requirements apply where the stack has a practical type checker, whether or not
the repo configures one. Practical means maintained, and able to check the repo's
existing code without rewriting it. So a Python repo needs one, such as mypy or
pyright, Ruby such as Sorbet, and plain JavaScript through TypeScript with `checkJs`
or JSDoc. They're N/A for shell, SQL, config or docs only. In a mixed repo, apply them
per production language. The suppression requirement applies where the language can
hide a type error, as the planted violations in [checks.md](checks.md) list, so it's
N/A for Rust.

Record as static evidence the type checker, whether CI fails on it, and its
strictness, with the share of production lines opted out or checked loosely, such as
by a Sorbet sigil below `strict` or a mypy per-module override. Also record escape
hatches per 1,000 lines of production code, leaving out generated, vendored and test
code: `any`, non-null `!`, `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`,
`# type: ignore`, file-level opt-outs such as `# mypy: ignore-errors` or
`# pyright: basic`, `cast()` and `T.unsafe`, or the stack's equivalents. Leave out
Go's `interface{}` and `any`, which are often idiomatic. Save the searches for reruns.
Like exclusions, they let an agent silence a check instead of fixing the cause.

A language is **significant** if it has at least 5 files or 5% of lines. A file is a
tracked file of that type, leaving out generated and vendored code, lockfiles and data
fixtures. Dockerfiles and CI workflows are significant from one file, because they
build or run the code. Workflows are their own group, needing actionlint and no
formatter, but count towards YAML's totals, so one workflow alone doesn't make YAML
significant. When YAML is significant, its linter and formatter cover workflow files
too. Markdown includes `.mdx`. Shell, YAML, Markdown and SQL count like any other
language. JSON, TOML, XML and CSV aren't significant languages. Count with
`git ls-files` by extension, or scc or tokei if installed, and save the command for
reruns.
A **production language** is one the shipped code is written in, not docs, CI or
config.

A significant language is **linted and formatted** when CI fails on a linter and a
formatter check for its files. A language with no established formatter, such as a
Dockerfile, needs only the linter. Easy ones to miss: shell (shellcheck, shfmt),
Dockerfiles (hadolint), CI workflows (actionlint), YAML (yamllint), Markdown
(markdownlint) and SQL (SQLFluff). A formatter that rewrites files without failing
doesn't count.

Each check is **established**, a widely used, maintained tool, or **custom**, the
repo's own code, such as a grep script in CI. Custom checks count wherever a check is
required, for C and for conventions enforced, because they're better than nothing. B
needs established tools for every significant language, and for each production
language one that supports custom rules, so a new rule runs in the same editor, CI
step and hook as the standard ones. Examples are ESLint plugins, RuboCop custom cops,
golangci-lint module plugins, ArchUnit and dependency-cruiser. Where the main linter
has no plugin API, such as Ruff or Clippy, Semgrep or ast-grep in CI provides custom
rules. Custom checks may still run alongside these without failing B.

**Security scanning** has five kinds. Each applies where the stack offers a practical
tool for it, whether or not the repo configures one:

- **Secrets:** gitleaks or trufflehog. Applies to every repo.
- **Code:** a static analyser for each production language and framework, such as
  brakeman for Rails, bandit or Semgrep for Python, gosec for Go, or CodeQL.
- **Dependencies:** osv-scanner, npm audit, bundler-audit or Dependabot alerts, where
  the repo has dependencies.
- **CI workflows:** zizmor, where the repo has GitHub Actions.
- **Infrastructure and containers:** checkov or trivy (formerly tfsec), where the
  repo has Terraform, Kubernetes manifests or Dockerfiles that build a shipped or
  deployed image, not dev-container or CI-only ones.

A kind is **covered** when CI fails on the tool's findings. Dependabot alerts cover
dependencies when on. A scanner whose results only go to GitHub code scanning, through
default setup or a workflow (CodeQL, or any SARIF upload), covers code scanning only
when the rules response has a `code_scanning` rule. Both are read as in
[checks.md](checks.md). A fake credential the commands miss means secret scanning
isn't covered, whatever the config says, and one they catch means it is. A catch by a
hook alone counts only towards secrets checked before commit or push. A kind with no
tool is not covered, unless the host is GitHub and the read that could cover it
failed: the Dependabot alerts call for dependencies, or the rules call for code
scanning. Then it's left out, like merge rules. **Secrets checked before commit or
push** means a documented pre-commit or pre-push hook runs a secret scanner, or
GitHub push protection is on. A CI scan alone is too late, because a pushed secret
has leaked. Without a hook, unreadable push protection leaves this out.

Record as static evidence each kind, with its tool or none, per production language
and framework for code. Also record security suppressions per 1,000 lines of
production code, such as `# nosec`, `nosemgrep`, `gitleaks:allow`, entries in a
brakeman ignore file or gitleaks allowlist, and dismissed CodeQL alerts if `gh` can
read them. They're **checked** when a new one fails a check unless it gives a reason,
such as brakeman `--ensure-ignore-notes` or a lint rule requiring a justification, or
needs a required review, such as `CODEOWNERS` on the ignore file with reviews
required, or GitHub's delegated alert dismissal. This is N/A where no scanner the
repo runs can be suppressed.

**Conventions enforced** is the share of tool-enforceable conventions that a lint
rule or structural test enforces, in CI or a documented hook. [checks.md](checks.md)
says how to build the list, and how planted violations override it. It's N/A only
when the repo has no production code, such as docs or config only. Otherwise, with no
tool-enforceable convention in the docs or review history, it's 0%, so B and A aren't
met: an agent can't follow conventions nobody wrote down, and there's nothing to turn
into tooling.

Record as static evidence each significant language with its share of files and
lines, its linter and formatter, whether CI fails on them, and whether each is
established or custom. Also record conventions enforced, with how many conventions
are tool-enforceable and how many are judgment.

| Grade | Static | Measured |
|-------|--------|----------|
| F | No linter, formatter or other mechanical check. | No such checks, or no violations caught. |
| D | Tools are configured, but CI doesn't run them. | Catch rate above 0% and below 40%. |
| C | CI lints and formats every significant language, secret scanning is covered, code scanning is covered where the stack has a tool for it, and CI runs a type checker where the stack has one. | Catch rate at least 40%, CI lints and formats every significant language, secret scanning is covered, code scanning is covered where the stack has a tool for it, and CI runs a type checker where the stack has one. |
| B | | Catch rate at least 60%, CI lints and formats every significant language with established tools, each where one exists, with custom-rule support for each production language, conventions enforced at least 50% where it applies, every kind of security scanning covered where it applies, code scanning for each production language and framework, secrets checked before commit or push, test isolation where it applies, a coverage gate, a strict type checker where the stack has one, and the checks that caught violations are required to merge (optional). |
| A | | Catch rate at least 85%, established tools with custom-rule support, as for B, conventions enforced at least 80% where it applies, every kind of security scanning covered and secrets checked before commit or push, as for B, with security suppressions checked where it applies, plus CI-enforced module boundary checks and performance budgets on key paths, each where it applies, test isolation where it applies, a coverage gate at 95% or more, every excluded untested branch caught where it applies (for example by a lint rule or a check on coverage config), a strict type checker where the stack has one, every suppressed type error caught where it applies, and the checks that caught violations are required to merge (optional). |

**Coverage fix.** When there's no coverage gate, or it's below 95%, suggest a
branch-coverage gate on changed code at 95% or more, not a higher overall threshold.
It moves the untested-branch catch and the Guardrails grade, such as "Guardrails C to
B".

**Type-check fix.** When CI runs no type checker, or it isn't strict, name the checker
and setting for this stack, such as "turn on `strict` in tsconfig.json" or "add
`mypy --strict` to CI". It can move the type-error catch, and moves the Guardrails
grade, such as "Guardrails D to C" for a new checker or "C to B" for strict.

**Lint-rule fix.** When a significant language has no linter or formatter in CI, name
the tool and the CI step, such as "add markdownlint and shellcheck to CI". It moves
the Guardrails grade, such as "Guardrails D to C". When a tool-enforceable convention
isn't enforced, suggest turning it into a lint rule, naming the tool, such as an
ESLint `no-restricted-imports` entry, a RuboCop custom cop or a Semgrep rule beside
Ruff. Prefer a linter CI already runs, and group the conventions one tool can take.
With none documented, suggest writing down the conventions agents most often break
and enforcing them the same way. It moves conventions enforced, the
documented-convention catch and the Guardrails grade, such as "Guardrails B to A".

**Security fix.** When a kind of security scanning is missing, name the tool and where
it runs for this stack, such as "add brakeman to CI" or "add gitleaks to CI and as a
pre-commit hook", not "add security scanning". It can move the fake-credential catch,
and moves the Guardrails grade, such as "Guardrails D to C" for secret or code
scanning or "C to B" for the rest. When security suppressions aren't checked, name
the setting, such as brakeman `--ensure-ignore-notes`, for "Guardrails B to A".

Whether reviews are required and whether a `CODEOWNERS` file exists are evidence only,
and don't change the grade. `CODEOWNERS` counts as evidence of review only if review
is actually required.

## Not proven

Under the five grades, add a "Not proven" line in these cases, using the first that
applies:

- If Verification isn't measured: "Not proven: Verification was not measured, so the
  repo's ability to catch a wrong change is unknown."
- If Verification is measured but fewer than 3 categories are: "Not proven: too few
  categories were measured to judge the repo as a whole."

Otherwise leave the line out.
