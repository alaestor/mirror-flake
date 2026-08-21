---
name: handoff
description: 'Instructions for writing a handoff document.'
disable-model-invocation: true
---
# Writing a Handoff

Write a local handoff to `.claude/handoff.md` in one pass, overwriting if it exists.

These guidelines are to help you strategize; they aren't hard and fast rules, or mandatory section headers.

## What to cover

Think about how best to direct the new session to pick up from where you're leaving off:

- **The task and its current state** — what are you working on?
- **Decisions already settled and why** — what's been chosen and what was the rationale?
- **What's open** — what remains undecided or left over to do?
- **What the next agent should do first** — your instructions for immediate next steps.

## Files recommendations

- **What files the next session should read** to prepare for its task?
- **Recommend against certain files** you think they might try to read but that you know aren't relevant.
- **Mention gotchas and hiccups you ran into,** but only if you expect the next agent will encounter them during the pending work.

## What to omit

- Concluded history
- Fixed bugs
- Details not relevant to their task

## Approach

Try to give good advice. The point of this is to set them up for success by providing high-value, high signal-to-noise information by weighting your experiences against future relevancy. This isn't a compaction summary: you're giving the next _you_ what they need to hit the ground running.

Reason what a good handoff should contain, and then write it.
