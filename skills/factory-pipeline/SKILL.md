---
name: factory-pipeline
description: >
  Run a multi-step coding pipeline (PRD → plan → ralph TDD loop → review → pr)
  by acting as an orchestrator that delegates each step to a fresh subagent via
  the Task tool, gating on artifacts written under `.factory/runs/<id>/`.
  Models the factory framework (github.com/alexopalic/factory) as a skill.
  TRIGGER on: "run factory", "factory this PRD", "dogfood this PRD",
  "$factory-pipeline <prd-path>", "/factory-pipeline <prd-path>",
  or when the user hands you a PRD/plan file under `plans/` and asks to
  execute it end-to-end.
allowed-tools: Bash Read Write Edit Glob Grep Task
metadata:
  author: Alexander Opalic
  version: "0.1.0"
---

# Factory Pipeline (orchestrator skill)

You are the **orchestrator**. You do not write production code yourself. You
delegate each step to a **fresh subagent** via the `Task` tool, then gate on
the artifact it wrote before moving on.

This is the skill-shaped version of the [`factory`](https://github.com/alexopalic/factory)
framework. The motivation and design trade-offs live in
[references/architecture.md](references/architecture.md) — read it once per
session before your first run, then keep this file in context.

## Arguments

```
$factory-pipeline <prd-path> [--resume <run-id>] [--from <step>]
```

- `<prd-path>` — required on first run. Markdown file describing what to build.
- `--resume <run-id>` — pick up an existing run from its manifest.
- `--from <step>` — start from a specific step (`plan` | `ralph` | `review` | `pr`).
  Implies you trust prior artifacts; useful for debugging.

## Run state

Every run lives under `.factory/runs/<id>/`:

```
.factory/runs/<id>/
├── prd.md            # copy of the input PRD
├── plan.md           # output of step 1
├── tickets/          # one file per ticket from plan.md
├── manifest.json     # state machine: which step ran, exit code, artifact path
└── events.jsonl      # append-only log
```

Initialize a run with:

```bash
bash skills/factory-pipeline/tools/init_run.sh "<prd_path>"
```

This prints the run id, copies the PRD in, and exports `FACTORY_RUN_DIR`.
Use that variable in every subsequent command.

## Pipeline

Execute steps **strictly in order**. Do not skip ahead. Do not parallelize
across steps (parallelism within `ralph` across tickets is allowed — see below).

### 1. plan

- Delegate: `Task(subagent_type: general-purpose, prompt: <contents of steps/plan.md> + "\nFACTORY_RUN_DIR=$FACTORY_RUN_DIR")`.
- Expected artifact: `$FACTORY_RUN_DIR/plan.md`.
- Gate: file exists, parses as the shape specified in `steps/plan.md`
  (frontmatter with `branch` + `title`, at least one ticket).
- On gate fail: retry once with the parser error appended. On second fail,
  abort and surface the run dir.

### 2. ralph (TDD loop, one subagent per ticket)

- Read `$FACTORY_RUN_DIR/plan.md`, split it into ticket files under
  `$FACTORY_RUN_DIR/tickets/T<n>.md`.
- For each ticket, spawn **one** subagent with `steps/ralph.md` as the prompt
  plus the ticket path. Subagents are independent and write one commit each.
- You may spawn multiple ticket-subagents in parallel **only if** the plan
  marks them as `[parallel-safe]`. Otherwise run them sequentially on the
  same branch to avoid merge churn.
- Gate per ticket: the ticket's "Done when" assertions pass (typecheck +
  tests green, files touched match the ticket's `files:` field).
- If a ticket fails after 3 retries, mark it `FAILED` in the manifest and
  continue with the rest. Do not block the pipeline on one bad ticket.

### 3. review

- Delegate: `Task` with `steps/review.md` against the branch diff.
- Expected artifact: `$FACTORY_RUN_DIR/review.md` (a findings list).
- Gate: artifact exists. Severity-`high` findings block step 4 — surface them
  and stop. Severity-`low`/`info` findings are noted but do not block.

### 4. pr

- Delegate: `Task` with `steps/pr.md`. The subagent opens the PR using
  `gh pr create`, drawing title from `plan.md` frontmatter and body from
  the ticket summaries.
- Gate: PR URL printed.

## Delegation rules (non-negotiable)

These rules are the entire point of the skill. If you violate them, you
collapse to "Claude doing everything in one context," which is what factory
exists to avoid.

1. **Never inline a step's work.** If you find yourself opening a source file
   to edit it, stop — that's a subagent's job. You only read artifacts under
   `$FACTORY_RUN_DIR/`.
2. **One Task call = one step (or one ticket).** Fresh context is the whole
   point.
3. **Pass the step prompt verbatim.** Don't paraphrase `steps/<name>.md` —
   `Read` the file and pass its body as the Task prompt.
4. **Gate before continuing.** Every step has a deterministic gate. Run it.
   Do not "trust the subagent said it's done."
5. **Append every state change to `events.jsonl`** via
   `tools/emit_event.sh <step> <status> <detail>`. The manifest is derived
   from events; never hand-edit it.

See [references/delegation-rules.md](references/delegation-rules.md) for the
reasoning and worked examples.

## Stop conditions

- Plan has zero tickets → abort, ask the user to refine the PRD.
- Any step exceeds 3 retries → abort, surface `$FACTORY_RUN_DIR/`.
- User Ctrl-Cs → write a `PAUSED` event so `--resume` can pick up cleanly.

## Resume semantics

If invoked with `--resume <run-id>`:

1. Read `.factory/runs/<id>/manifest.json`.
2. Find the first step whose latest event is not `DONE`.
3. Resume from that step. Earlier artifacts are trusted as-is.

## Output to the user

After each step, one line: `[step] <status> — <artifact path>`.
At the end of a run, print the PR URL and the run dir. Nothing else.

## What this skill does NOT do

- It does not implement the harness subprocess model (claude/codex/copilot).
  In skill form, the Task tool is the harness — there's only one model.
- It does not handle multi-repo or cross-repo PRs.
- It does not write the steps' prompts for you. Customize `steps/*.md` to
  match your project's conventions before running.
