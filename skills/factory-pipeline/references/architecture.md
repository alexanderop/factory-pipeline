# Architecture

This skill ports the [`factory`](https://github.com/alexanderop/factory) idea
into Claude Code's Skill + Task primitives.

## What factory does

Factory is a TypeScript framework for **software factories** — multi-step
coding pipelines that run AFK on top of whichever coding harness you already
have installed (`claude`, `codex`, `copilot`). Each step is a markdown prompt;
the orchestrator wires them together; harnesses run as subprocesses and pass
artifacts via a filesystem-rooted run directory.

Key design choices factory inherits, all of which this skill keeps:

1. **Sequential steps with deterministic gates.** A step does not start until
   the previous step's artifact passes a programmatic check.
2. **Fresh agent context per step.** Long-running sessions accrete failed
   attempts and biased priors. Each step gets a clean slate plus the previous
   artifact.
3. **Filesystem as state.** All inter-step state lives under
   `.factory/runs/<id>/`, not in conversation memory. This makes runs
   resumable and inspectable after the fact.
4. **Step prompts are user-editable markdown.** Not code, not config — just
   markdown files under `steps/`. Customize per project.

## Why this maps to Skills

| factory concept              | Skill equivalent                         |
| ---------------------------- | ---------------------------------------- |
| Pipeline definition          | `SKILL.md` body                          |
| Step markdown                | `steps/*.md` bundled files               |
| Harness subprocess           | `Task` tool spawning a subagent          |
| `$FACTORY_RUN_DIR`           | `.factory/runs/<id>/` — same convention  |
| `RunManifest` + resume       | `manifest.json` + `events.jsonl`         |
| Capability gates             | Scripts under `tools/`                   |
| `maxIters` per step          | Retry loop in the orchestrator (3 tries) |

## What is intentionally lost in translation

- **No multi-harness routing.** Factory picks among installed CLI binaries.
  Here, there's only one model, so the Task tool is the only worker.
- **No OTEL spans.** Factory exports rich observability; this skill writes a
  JSONL event log instead. Sufficient for one-machine debugging.
- **No durable workflow.** Factory's roadmap includes Effect Cluster-backed
  durability. A Skill run lives inside one Claude Code session; if you kill
  the session, you resume manually with `--resume <run-id>`.

## When to prefer factory itself over this skill

Use the real `factory` framework when:

- You want to mix harnesses (e.g., plan with Claude, ralph with Codex).
- You want OTEL spans piped into a dashboard.
- The pipeline must outlive any single editor session.
- You want typed Effect services and not markdown-glued bash.

Use this skill when:

- You're already inside Claude Code and want the pipeline shape without
  setting up a TypeScript project.
- You want to prototype a pipeline before promoting it to real factory steps.
- The work is small enough that one model and one session is fine.

## References

- factory README: https://github.com/alexanderop/factory
- factory's own CLAUDE.md describes the "fresh agent context per task" rule
  that this skill operationalizes.
