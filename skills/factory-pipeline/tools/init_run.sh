#!/usr/bin/env bash
# init_run.sh — create a fresh factory run directory and copy the PRD in.
# Usage: bash tools/init_run.sh <prd_path>
# Prints: the absolute path of the run dir on stdout. The orchestrator
# captures it and uses it as $FACTORY_RUN_DIR for the rest of the run.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <prd_path>" >&2
  exit 2
fi

PRD_PATH="$1"

if [[ ! -f "$PRD_PATH" ]]; then
  echo "error: PRD file not found: $PRD_PATH" >&2
  exit 1
fi

# Run id: ULID-ish — sortable, unique enough for one machine.
# Falls back to date+random if `uuidgen` is missing.
if command -v uuidgen >/dev/null 2>&1; then
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen | tr 'A-Z' 'a-z' | cut -c1-8)"
else
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
fi

RUN_DIR=".factory/runs/$RUN_ID"
mkdir -p "$RUN_DIR/tickets"

cp "$PRD_PATH" "$RUN_DIR/prd.md"

# Minimal manifest. Events appended later derive the rest.
cat > "$RUN_DIR/manifest.json" <<EOF
{
  "run_id": "$RUN_ID",
  "prd": "$PRD_PATH",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "INIT"
}
EOF

# Touch the events log so consumers can `tail -f` it.
: > "$RUN_DIR/events.jsonl"

# Absolute path — the orchestrator passes this as FACTORY_RUN_DIR.
ABS_DIR="$(cd "$RUN_DIR" && pwd)"
echo "$ABS_DIR"
