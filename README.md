# factory-pipeline

A Claude Code skill that runs a multi-step coding pipeline
(**PRD → plan → ralph (TDD loop) → review → pr**) by acting as an
**orchestrator** and delegating each step to a fresh subprocess of the
**user-chosen coding harness** — `claude`, `codex`, or `copilot`. State lives
on the filesystem under `.factory/runs/<id>/` so runs are inspectable and
resumable.

## Usage

```
$factory-pipeline plans/auth.md                            # default harness: claude
$factory-pipeline plans/auth.md --harness codex
$factory-pipeline plans/auth.md --harness copilot
$factory-pipeline plans/auth.md --resume 20260511T102314Z-9a8b7c6d
$factory-pipeline plans/auth.md --from review
```

The trigger also fires on natural language: *"factory this PRD with codex"*,
*"use copilot to ralph these tickets"*, *"dogfood this plan"*.

What it will do:

1. `bash tools/init_run.sh <prd>` — create `.factory/runs/<id>/`, copy the
   PRD in, set `FACTORY_RUN_DIR`.
2. **plan** — `run_step.sh <harness> plan`. Worker writes `plan.md`. Gate
   with `tools/validate_plan.py`.
3. **ralph** — for each ticket in the plan,
   `run_step.sh <harness> ralph $ticket`. One commit per ticket, tests-first,
   gates on typecheck + tests + ticket scope.
4. **review** — `run_step.sh <harness> review`. Worker writes `review.md`.
   High-severity findings block the next step.
5. **pr** — `run_step.sh <harness> pr`. Worker opens the PR via `gh`.

Every state change appends one JSON line to
`.factory/runs/<id>/events.jsonl`. The manifest is derived; never edit by hand.

## Harness invocations

The same step prompt is fed into whichever CLI was picked. `tools/run_step.sh`
builds the right argv per harness:

| harness   | argv `run_step.sh` produces                                            |
| --------- | ---------------------------------------------------------------------- |
| `claude`  | `claude --dangerously-skip-permissions -p "<prompt>"`                  |
| `codex`   | `codex exec --dangerously-bypass-approvals-and-sandbox "<prompt>"`     |
| `copilot` | `copilot --allow-all -p "<prompt>"`                                    |

All three are unattended modes — the orchestrator gates artifacts, so an
interactive permission prompt would deadlock the run. If a harness isn't on
`$PATH`, the script exits 127 with a clear message. Adding a fourth harness
is a `case` branch in one shell script.

## What it deliberately does NOT do

- **No mixing harnesses within a run.** One `--harness` value applies to
  every step. Use separate runs with `--from` if you want to bench claude
  against codex on the same plan.
- **No OTEL spans.** Events go to JSONL; sufficient for one-machine debugging.
- **No durable workflow.** A run lives in one host session. Kill the host,
  resume manually with `--resume <run-id>`.
- **No auto-merge.** The `pr` step opens the PR and stops.

## Installation

```bash
npx skills add https://github.com/alexanderop/factory-pipeline --skill factory-pipeline
```

Or copy `skills/factory-pipeline/` into your project's `.claude/skills/`.

You also need at least one of `claude`, `codex`, `copilot` on `$PATH`. None of
them are installed by this skill.

## Structure

```
skills/factory-pipeline/
├── SKILL.md                          # the orchestrator prompt
├── references/
│   ├── architecture.md               # the 5 design choices, in detail
│   └── delegation-rules.md           # the 5 rules with worked examples
├── steps/
│   ├── plan.md                       # worker prompt: PRD → plan.md
│   ├── ralph.md                      # worker prompt: ticket → one TDD commit
│   ├── review.md                     # worker prompt: diff → findings
│   └── pr.md                         # worker prompt: branch → PR via gh
└── tools/
    ├── init_run.sh                   # create run dir, print FACTORY_RUN_DIR
    ├── run_step.sh                   # invoke <harness> with a step prompt
    ├── emit_event.sh                 # append one JSON line to events.jsonl
    └── validate_plan.py              # plan-step gate
```

## Why this exists

Long sessions accrete failed attempts and biased priors — the orchestrator
ends up second-guessing itself by step 3. This skill enforces fresh context
per step by spawning a new subprocess of the chosen harness for each: plan,
every ticket, review, pr. The orchestrator only reads artifacts and runs
gates, never writes code itself.
