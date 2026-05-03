#!/usr/bin/env bash
# Symphony hook: after_create
# Runs ONCE when a new workspace is created for an issue. Failure here aborts the run.
#
# Responsibilities:
#   1. Dump initial ticket thread to context file (so first attempt has prior comments).
#   2. Dump issue body to a file the agent prompt can include.

set -euo pipefail
source "$(dirname "$0")/../lib/plane.sh"

CONTEXT_DIR="$SYMPHONY_WORKSPACE/.symphony"
mkdir -p "$CONTEXT_DIR"

# 1. Dump comments (likely empty on a fresh card, but harmless).
plane_dump_comments "$CONTEXT_DIR/ticket-thread.md" 50

# 2. Dump issue body for the agent.
ISSUE_BODY_FILE="$CONTEXT_DIR/issue-body.md"
plane_api GET "/projects/$SYMPHONY_PROJECT_ID/work-items/$SYMPHONY_ISSUE_ID/" \
  | jq -r '.description_stripped // .description_html // ""' \
  > "$ISSUE_BODY_FILE"

# Export the path so subsequent hooks + the prompt builder can reference it.
echo "SYMPHONY_TICKET_THREAD_FILE=$CONTEXT_DIR/ticket-thread.md"
echo "SYMPHONY_ISSUE_BODY_FILE=$ISSUE_BODY_FILE"
