---
name: get-aligned
description: >-
  Interview the user until you both agree on the goal and outcome of a task,
  leaving how it gets built to you. Use before starting work whose intent is
  ambiguous, or substantial work where different unstated purposes would change
  the result, or when the user says "get aligned", "let's align", "make sure
  we're on the same page", "check what I actually want", or "ask me questions
  before you start". Not for stress-testing a plan's mechanics.
---

# Get aligned on the outcome

Interview the user until you both hold the same picture of the **goal and the
outcome**: what should be true when this is done, for whom, why it matters, and
how you would both know it worked. How to build it is yours to decide
afterwards. The tone is collaborative, not adversarial, but push back when the
goal is vague or two wants conflict.

## Check what's written down first

Before the opening statement, skim what's relevant and visible without asking:
the request's wording, any repo docs (README, AGENTS.md or CLAUDE.md, roadmap,
decision records, documented principles) and recent commits. Look for a stated
goal this work naturally sits under.

Don't ask what's written down; state it as a guess the user can correct, since
docs can be stale or aspirational. A conflict with a documented goal or
principle goes on the Frontier as a question. If no written goal fits, say so
and give your best guess from the request; don't force a connection.

## Start from a restatement

Open by stating the goal back in two or three sentences: the outcome, what
success looks like, and the higher purpose you guess it serves. Mark anything
you inferred rather than heard.

Then state your assumptions. It's hard to list what you forgot to mention but
easy to spot when someone has it wrong, so these are guesses informed by the
evidence, not questions. Run through where unsaid context usually sits and
state a concrete guess for any that could change the outcome, without repeating
the purpose:

- **What it feeds into**: what happens with the result next, or what larger
  work it's part of.
- **Who it's for**: who actually uses or sees it.
- **How long it lasts**: a throwaway or something to maintain.
- **What wins in a trade-off**: speed, polish or safety, for example.
- **Why now**: what triggered it, such as an incident, a deadline or a request
  from someone.

Skip any that wouldn't change it; on most tasks that leaves two or three.

Point to your shakiest guess, the one that would cost the most if wrong, and
say what you'd do differently. If no guess would change the outcome, say so and
skip this.

> I'm assuming this is a one-off for the migration and that speed matters more
> than polish. The one-off part is my shakiest guess: if you'll keep using this,
> I'd add tests and make the paths configurable. Correct me on anything that's
> off.

End with that invitation to correct. If other questions are open, send this
with the first one and make the shaky guess that question, stated once. If
nothing else is open, it goes in the single message described below.

If anything is still open after that, it's usually one of these:

- **Done**: what does finished look like, who notices, and how would it be
  judged?
- **Out of scope**: what is deliberately not part of this?
- **Hard constraints**: a deadline, a budget, something that must not break.

### Asking about the purpose

Climb to a higher purpose only if the answer could change the outcome; that's
usually one or two levels, and at most two purpose questions. Skip them when
the purpose is obvious or the task is small.

When two purposes lead to different outcomes, ask a fork as a normal
multiple-choice question: "If this is for X I'd build A, if it's for Y I'd
build B."

## Ask only what the user alone can answer and that changes the outcome

Before asking anything, check two things. Could you find the answer yourself
(in the codebase, a tool, a document)? Then look it up. Would a different
answer change what the user ends up with, or how they'd judge it? If not, it's
a *how* question: decide it yourself.

A how question earns a place only when its answer shows up in the outcome:
behaviour someone notices, scope, cost, risk, time, or reversibility. Ask it as
that consequence, not as the mechanism: "should a reviewer see every retry?",
not "should retries get their own table?".

Applied honestly, this leaves few questions, and sometimes none. A clear
request still gets the opening statement, since a well-specified request is not
evidence the purpose was shared; only the further questions can be skipped.
With none to ask, send one message covering the opening statement and the
read-back (see Done), saying each thing once, including who it's for.

Don't block on lookups: only the questions that depend on a running lookup
wait for it. Keep going and fold the findings in when they land.

## Rounds and the frontier

The **frontier** is every open question whose prerequisites are settled: the
ones you can ask now without guessing at answers you haven't heard. Each round
takes the current frontier. Open it with a one-line scope note (how many
questions, what they cover) in the same message as its first question.

Ask **one question per turn** and wait for the answer; a batch gets diluted
answers, and an early answer often reshapes the later ones. Put the questions
most likely to reshape the rest first.

### Keep the state in a ledger file

Don't hold the frontier in your head. Before the first question or read-back,
create a ledger file outside the repo (the session scratchpad if there is one)
and update it after every answer, before asking the next question. With no
questions to ask, a few lines covering the goal, purpose and assumptions are
enough:

```markdown
# Alignment: <topic>

## Goal (draft)
<the current restatement; rewrite it as answers change it>

## Purpose
<the higher purpose this serves> (guess or confirmed)

## Assumptions
- Lifespan: one-off for the migration (guess)
- Trade-off: speed over polish, corrected from polish first (confirmed)

## Settled
- Q2 Audience: internal reviewers only, over customers too (user)
- Q3 Retry visibility: every retry shown, over final result only (delegated)

## Frontier
- Q4 <question you can ask now>

## Waiting
- Q6 <question>: needs Q4 / needs lookup of <fact>

## Left to me
- <how decision you'll make without asking>
```

Every question lives in exactly one of Settled, Frontier or Waiting. When an
answer lands, move it to Settled, then promote any Waiting question whose
prerequisites are now met. An empty Frontier with an empty Waiting list means
the questions are done. Record corrections in Assumptions. When a guess becomes
a question, move it out of Assumptions; Settled holds the answer. Check Settled
and Assumptions before asking anything, so you never re-ask a decision or a
correction. Tell the user where the file is once, when you create it.

### Asking a question

Ask each as **multiple choice**, with `AskUserQuestion` in Claude Code or a
numbered list of options where there's no such tool. Put the framing in the
message before the question, since option descriptions are too short to hold it:

```
❓ **Q4 — <question title>** _(2/5 this round)_: <the context, the trade-off,
and what hangs off the answer>
```

```
header: "<topic label>"
question: "<the decision, restated in one line>"
options:
  - label: "<your recommendation> (Recommended)"
    description: "<what this means, and its one-line reason>"
  - label: "<alternative>"
    description: "<what this means, and what it costs>"
```

Your recommendation goes first so the user can accept in a click and spend
their effort where you're wrong. Offer only genuinely distinct options. Number
questions continuously across the session (Q1, Q2, …), not per round, so any
answer can refer back unambiguously.

A question that asks the user to *produce* something rather than *choose* (a
name, a threshold, a description of who the users are) stays prose. Don't
invent options to force it into a menu.

## Processing answers

Each answer can settle a later question, change what it should ask, or open new
ones. Rework the rest of the round accordingly and say so, rather than asking
something the last answer made stale. When the round is exhausted, recompute
the frontier.

- **Settled is settled.** Never re-ask a decision the user made with the
  trade-off in view. If a later answer contradicts an earlier one, surface the
  conflict and ask which holds.
- **A dodged question stays open.** Say so and re-ask.
- **"Whatever you think" settles it with your recommendation.** It also means
  you've drifted into how territory, so stop asking in that direction. Record
  it as delegated, not a user choice, so the read-back gives them one more look.

## Done

You're done when the ledger's Frontier and Waiting lists are empty and every
assumption that would change the outcome is confirmed, or named as unconfirmed
in the read-back. The goal is to surface what the user already knows, not to
anticipate every change of mind: changing it later, after seeing a concrete
result, doesn't mean alignment failed.

Close with a read-back built from the ledger, omitting empty sections:

1. **Goal and outcome**, including who it's for.
2. **Purpose**, and any assumption still unconfirmed: "Unconfirmed: X.
   Confirming this means going ahead on X."
3. **Success criteria**: how you'll both know it worked.
4. **Out of scope** and **hard constraints**.
5. **Settled decisions**, each with what it was chosen over. Flag the delegated
   ones.
6. **Left to me**: the main how decisions you'll make without asking, a line
   each, so the user can pull one back if it matters to them.

Get the user's explicit confirmation that this is the shared picture. Do not
start the work until they confirm. Confirming the read-back settles anything it
names as unconfirmed; mark those confirmed. Keep the ledger afterwards: it is
the brief the work is checked against. Check the how decisions against its
Purpose line. If a better route to the purpose would change the agreed outcome,
stop and ask; if it wouldn't, take it and mention it in your summary.

### Render the read-back visually when it earns it

Past roughly five settled decisions, or when the subject is something a picture
states directly (a flow, a set of states, a before-and-after, a budget that
sums to a whole), also publish the read-back as an artifact. Use
`artifact-diagramming` for the figures. Without artifact publishing, the prose
read-back stands.

- **Draw the outcome, not the decision list.** A styled table is still prose.
  Show what the decisions produce: the screen before and after, the states a
  request moves through, where the time or money goes.
- **The visual is in addition, never instead.** Every settled decision still
  appears in the prose with what it was chosen over.

Publishing is not confirmation.
