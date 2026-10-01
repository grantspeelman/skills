---
name: auto-alignment-before-action
description: >-
  Alignment gate between a user's request and acting on it. Use whenever the
  user asks for something that would change state (write or edit files, run
  commands with side effects, commit, push, publish, delete, install, or
  message anyone), before taking the first action. Checks whether you and the
  user share the same picture of the goal and outcome; if not, closes the gap
  with the get-aligned skill first. Not needed for pure questions,
  explanations, or read-only lookups.
---

# Don't act until we agree on the outcome

The user wants to talk naturally without invoking anything by hand. This skill
is the gate between understanding a request and acting on it. **Do not act
unless you are certain you and the user agree on what the result should be.**
If you aren't, get there with the `get-aligned` skill first.

The gate is about the outcome, not the method. How to build what was agreed is
yours to decide, so an open implementation choice is never a reason to stop.

## What counts as acting

**Acting** changes state: creating, editing, moving or deleting files; running
commands with side effects; installing things; committing, pushing, publishing
or deploying; sending or posting anything.

**Not acting** needs no gate: answering, explaining, reading, searching,
running read-only commands. Gathering facts is your job, and it's often how
you get certain without asking.

## The outcome check

Before acting, silently answer these. Each answer must trace back to something
the user said or a settled source: a `get-aligned` ledger for this work, a
project file such as `CLAUDE.md`, or a decision already confirmed in this
conversation. An answer you inferred doesn't count.

1. **Goal:** why does the user want this, and what problem goes away?
2. **Outcome:** what will exist or be different when you're done, and who
   notices?
3. **Scope:** what's in, and what's explicitly out?
4. **Constraints:** what rules, preferences or earlier decisions apply?
5. **Done:** how will the user judge that it worked?

Then ask: **if one of my assumptions is wrong, would the user see a different
result than they expected?** If yes, it's a gap. If the assumption only
changes how the work is done and the user would never notice, it isn't a gap:
decide it.

- **All five traced, no outcome-changing assumptions:** you're aligned. Go to
  *Acting*.
- **Any gap:** close it first. When in doubt, it's a gap; the user asked for
  certainty, not a good guess.

## Closing the gap

Close what you can yourself first: read the files, search, check earlier
decisions. Only what's left goes to the user.

- **One small gap:** ask a single question in `get-aligned`'s question format,
  then re-run the check.
- **More than one gap, or anything expensive or hard to undo:** run a full
  `get-aligned` session. Its ledger and the user's confirmed read-back become
  the shared understanding you act on.

Never start the work while a question is outstanding.

## Acting

Once aligned, open with **one line** naming the outcome you're about to
produce and any point you're deciding on the user's behalf. For example:
"Adding an RSS feed for the blog, feed only, no sitemap yet." That line is the
user's last cheap chance to stop you, so make it specific, not "on it".

### Out clauses

Under that line, before you start, look at the request and guess the two to
four issues most likely to get in the way: a network or auth failure, a
missing dependency or permission, a failing test you didn't cause, data that
doesn't look the way the request assumes. For each, recommend one of:

- **I'll try to fix it**, when the fix is local, reversible and doesn't touch
  anything the user didn't ask you to touch.
- **I'll stop and tell you**, when fixing it means changing credentials,
  config or systems outside the task, spending money, waiting a long time, or
  guessing at something only the user knows.

```
Out clauses:
- npm registry unreachable → stop and tell you
- lint fails on files I didn't touch → leave them, mention at the end
- feed validator rejects the dates → I'll fix the formatting myself
```

These are a sample of categories, not an exhaustive rulebook. They tell you
what kind of problem the user wants handed back and what kind they're happy
for you to solve. When an issue you didn't predict comes up, judge it by the
closest clause.

If a `get-aligned` session ran, put the out clauses in its read-back so one
confirmation covers both. Otherwise, for work that is long, hard to undo or
reaches outside the repo, wait for the user to accept or adjust them before
starting. For quick, reversible work, state them and go. Skip them entirely
for the small direct changes under *Don't over-ask*. Record the accepted out
clauses in the ledger if there is one.

## Mid-task

Once the work has started, keep going. Stop in two cases only:

- **You hit a blocker an out clause says to hand back**, or one closest to
  such a clause. Stop at that point, say what happened and what you tried, and
  recommend a next step. Don't keep trying workarounds.
- **You're about to change the goal or outcome agreed upfront**: a different
  result than the one confirmed, something moving in or out of scope, or
  success being judged differently. Stop before doing it, say what would
  change and why, and get the user's answer. Don't change the outcome
  silently, and don't push on and flag it at the end.

Record either decision in the ledger if there is one. Everything else is yours
to decide as you go: new implementation choices, problems the out clauses say
you can fix, a plan that needs reworking to reach the same outcome.

## Don't over-ask

- **Settled is settled.** Never re-ask what the user decided or what a ledger
  or project file already answers.
- **Small, reversible changes the user asked for directly** (fix this typo,
  rename this variable) are aligned by definition. Say the one line and do it.
- **"Just do it" or "whatever you think"** settles open points with your
  recommendation. Name them as delegated in your opening line, and in the
  ledger if there is one.
