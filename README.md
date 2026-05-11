# factory-pipeline

A Claude Code skill that runs a multi-step coding pipeline
(**PRD → plan → ralph (TDD loop) → review → pr**) by acting as an
**orchestrator** and delegating each step to a fresh subagent via the `Task`
tool. State lives on the filesystem under `.factory/runs/<id>/` so runs are
inspectable and resumable.

This is the skill-shaped port of the [`factory`](https://github.com/alexopalic/factory)
TypeScript framework — same pipeline shape, same fresh-context-per-step
discipline, but it runs inside a single Claude Code session instead of
shelling out to harness binaries.

## Usage

```
$factory-pipeline plans/observability-trace-narrative.md
$factory-pipeline plans/auth.md --resume 20260511T102314Z-9a8b7c6d
$factory-pipeline plans/auth.md --from review
```

What it will do:

1. `bash tools/init_run.sh <prd>` — create `.factory/runs/<id>/`, copy the
   PRD in, set `FACTORY_RUN_DIR`.
2. **plan** — `Task` a subagent with `steps/plan.md`. Expect `plan.md` back.
   Gate with `tools/validate_plan.py`.
3. **ralph** — for each ticket in the plan, `Task` a subagent with
   `steps/ralph.md`. One commit per ticket, tests-first, gates on
   typecheck + tests + ticket scope.
4. **review** — `Task` a subagent with `steps/review.md` against the branch
   diff. Writes `review.md`. High-severity findings block the next step.
5. **pr** — `Task` a subagent with `steps/pr.md`. Opens the PR via `gh`.

Every state change appends one JSON line to
`.factory/runs/<id>/events.jsonl`. The manifest is derived; never edit by hand.

## What it deliberately does NOT do

- **No multi-harness routing.** factory itself picks among `claude`, `codex`,
  `copilot`. Here the Task tool is the only worker.
- **No OTEL spans.** Events go to JSONL; sufficient for one-machine debugging.
- **No durable workflow.** A run lives in one session. Kill the session,
  resume manually with `--resume <run-id>`.
- **No auto-merge.** The `pr` step opens the PR and stops.

## Installation

```bash
npx skills add https://github.com/alexopalic/factory-pipeline --skill factory-pipeline
```

Or copy `skills/factory-pipeline/` into your project's `.claude/skills/`.

## Structure

```
skills/factory-pipeline/
├── SKILL.md                          # the orchestrator prompt
├── references/
│   ├── architecture.md               # mapping to factory, what's lost in translation
│   └── delegation-rules.md           # the 5 rules with worked examples
├── steps/
│   ├── plan.md                       # subagent prompt: PRD → plan.md
│   ├── ralph.md                      # subagent prompt: ticket → one TDD commit
│   ├── review.md                     # subagent prompt: diff → findings
│   └── pr.md                         # subagent prompt: branch → PR via gh
└── tools/
    ├── init_run.sh                   # create run dir, export FACTORY_RUN_DIR
    ├── emit_event.sh                 # append one JSON line to events.jsonl
    └── validate_plan.py              # plan-step gate
```

## When to prefer real factory over this skill

- You want to mix harnesses (plan with Claude, ralph with Codex, etc.).
- You want OTEL spans piped into a dashboard.
- The pipeline must outlive any single editor session.
- You want typed Effect services and not markdown-glued bash.

When to prefer this skill:

- You're already inside Claude Code and want the shape without setting up
  a TypeScript project.
- You want to prototype a pipeline before promoting it to real factory steps.
- The work is small enough that one model and one session is fine.

## Why this exists

Long sessions accrete failed attempts and biased priors — the orchestrator
ends up second-guessing itself by step 3. factory solves this with fresh
subprocess context per step; this skill solves it with the Task tool. Same
discipline, less infrastructure.

## Reference

- factory: https://github.com/alexopalic/factory
- The "fresh agent context per task" principle is documented in factory's
  own `CLAUDE.md`.
