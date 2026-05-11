# Delegation rules — the reasoning

The orchestrator's whole job is to *not* do the work. This file expands the
five rules in `SKILL.md` with worked examples and failure modes.

## Rule 1 — Never inline a step's work

**Wrong:**

```
User: $factory-pipeline plans/auth.md
Orchestrator: I'll plan first... <opens auth.md, drafts plan inline, edits files itself>
```

**Right:**

```
User: $factory-pipeline plans/auth.md
Orchestrator: bash tools/init_run.sh plans/auth.md
              → FACTORY_RUN_DIR=.factory/runs/01HXYZ
              Task(prompt: <steps/plan.md body> + run dir)
              → subagent writes plan.md
              Read $FACTORY_RUN_DIR/plan.md
              → gate passes, continue
```

Symptom you're violating this rule: you `Read` or `Edit` a source file that
is not under `$FACTORY_RUN_DIR/`. The moment that happens, stop and delegate.

## Rule 2 — One Task call = one step (or one ticket)

Subagent context isolation is load-bearing. If you bundle "plan and ralph" or
"review and pr" into one Task call, the subagent inherits the planning context
when implementing, which is exactly the prior-bias factory exists to avoid.

The one exception: within `ralph`, you may launch N parallel subagents — one
per ticket — *if* the plan marks tickets `[parallel-safe]`. They share no
context with each other; each only sees its one ticket file.

## Rule 3 — Pass the step prompt verbatim

`Read` the file from disk and pass its body. Do not summarize it. Do not
"improve" it on the fly. Two reasons:

- The prompts are tuned. Paraphrasing drifts.
- Reproducibility — if a run fails, the user needs to know exactly what the
  subagent saw.

Append, don't rewrite. The pattern is:

```
<contents of steps/<name>.md>

---
FACTORY_RUN_DIR=<absolute path>
<any step-specific args, e.g. ticket path>
```

## Rule 4 — Gate before continuing

Every step has a deterministic check. Examples:

- `plan` gate: `plan.md` exists, has valid frontmatter, has ≥1 ticket.
- `ralph` ticket gate: `git diff --stat HEAD~1` matches the ticket's `files:`
  field within tolerance; project's test command exits 0.
- `review` gate: `review.md` exists; parse for `severity: high` blocks.
- `pr` gate: stdout from the subagent contains a `https://github.com/.../pull/\d+` URL.

If the gate fails, retry **once** with the failure output appended to the
step prompt as additional context. If it fails again, abort.

## Rule 5 — Append to events.jsonl

Every state change writes one JSON line:

```json
{"ts":"2026-05-11T10:23:14Z","step":"plan","status":"START","run":"01HXYZ"}
{"ts":"2026-05-11T10:24:02Z","step":"plan","status":"DONE","artifact":"plan.md"}
{"ts":"2026-05-11T10:24:02Z","step":"ralph","status":"START","ticket":"T1"}
```

Use `tools/emit_event.sh <step> <status> <detail>` so the format stays
consistent. The manifest is derived — never hand-edit it.

## Common failure modes

- **"The subagent said it's done."** Doesn't matter. Run the gate.
- **"It's faster if I just edit this one file myself."** It's faster *this
  time*. Then the next pipeline run drifts because you set a precedent.
- **"The ticket needs context from the previous one."** That's a planning
  bug. Go back, re-plan, split or merge tickets so each is self-contained.
- **"I'll resume by re-running the whole thing."** Use `--resume <run-id>`.
  The manifest exists for this.
