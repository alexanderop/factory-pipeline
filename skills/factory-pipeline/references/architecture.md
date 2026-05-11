# Architecture

The reasoning behind the four design choices the skill makes. Read once per
session before your first run, then trust SKILL.md.

## 1. Sequential steps with deterministic gates

A step does not start until the previous step's artifact passes a
programmatic check (`tools/validate_plan.py`, `git diff --stat`, parsing
`review.md` for `severity: high`).

Why: model self-assessment is unreliable. "I think the plan is good" is not
the same as "the plan file has frontmatter, ≥1 ticket, and each ticket has a
Done-when clause." Gates make the difference observable and reproducible.

## 2. Fresh agent context per step

Each step (and each ticket inside `ralph`) gets its own `Task` invocation
with a clean context — only the step prompt plus the previous artifact.

Why: long sessions accrete failed attempts and biased priors. By step 3, an
agent that planned, then implemented, then reviewed its own code in one
context is second-guessing itself and missing things. Fresh context is the
single biggest correctness lever this skill pulls.

The corollary: subagents do not share knowledge. If a ticket "needs context
from a previous ticket," that's a planning bug — split or merge tickets so
each is self-contained.

## 3. Filesystem as state

All inter-step state lives under `.factory/runs/<id>/`, not in conversation
memory. The manifest is derived from `events.jsonl` (append-only). The
orchestrator never holds important state in its own head.

Why: runs are resumable and inspectable. Kill the session mid-run, come back
the next day, `--resume <run-id>`. Inspect a failed run by reading its dir —
no need to re-prompt the model to "remember what we did."

## 4. Step prompts are user-editable markdown

`steps/plan.md`, `steps/ralph.md`, `steps/review.md`, `steps/pr.md` are not
hard-coded. They are markdown files the orchestrator reads at runtime and
passes verbatim to subagents.

Why: every project has different conventions. The plan format you want for a
TypeScript monorepo is not the plan format you want for a Python data
pipeline. Editing the prompt is a 30-second change; editing TypeScript step
implementations is not.

## What this skill is not

- Not a durable workflow. A run lives inside one Claude Code session. If you
  kill the session, you resume manually with `--resume <run-id>`.
- Not multi-harness. Only the Task tool acts as the worker — there's one
  model in play, even though each call gets fresh context.
- Not an observability platform. State changes go to JSONL events. If you
  want spans in a dashboard, export them yourself.
- Not opinionated about project layout. The skill expects a git repo with
  some test/lint command; everything else is up to the step prompts you
  write.
