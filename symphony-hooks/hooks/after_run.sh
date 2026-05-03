#!/usr/bin/env bash
# Symphony hook: after_run
# Runs AFTER each attempt. Failures here are logged but ignored.
#
# Used for telemetry only — the lfg-symphony command itself posts step-level comments.
# Keep this hook side-effect-light so failures don't pollute the ticket thread.

set -euo pipefail
source "$(dirname "$0")/../lib/plane.sh"

# Symphony exposes attempt outcome via $SYMPHONY_ATTEMPT_RESULT (succeeded/failed/timed_out/...).
# When unset, treat as no-op.
RESULT="${SYMPHONY_ATTEMPT_RESULT:-unknown}"

# Append a short telemetry line to a per-issue log under the workspace.
LOG="$SYMPHONY_WORKSPACE/.symphony/attempts.log"
mkdir -p "$(dirname "$LOG")"
printf '%s\tattempt=%s\tresult=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$SYMPHONY_ATTEMPT" \
  "$RESULT" \
  >> "$LOG"
