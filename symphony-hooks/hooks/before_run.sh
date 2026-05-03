#!/usr/bin/env bash
# Symphony hook: before_run
# Runs before EACH attempt. Failure aborts the current attempt (Symphony will retry per its
# own policy). Load-bearing for the "Needs Decision" resume protocol — refreshes the ticket
# thread file so the agent sees the human's latest answer.

set -euo pipefail
source "$(dirname "$0")/../lib/plane.sh"

CONTEXT_DIR="$SYMPHONY_WORKSPACE/.symphony"
mkdir -p "$CONTEXT_DIR"

# Refresh ticket comments. The agent must read this file before every step.
plane_dump_comments "$CONTEXT_DIR/ticket-thread.md" 50

# Refresh issue body — humans can edit the description while the card is in flight.
plane_dump_issue_body "$CONTEXT_DIR/issue-body.md"

# Surface env to the agent prompt builder.
echo "SYMPHONY_TICKET_THREAD_FILE=$CONTEXT_DIR/ticket-thread.md"
echo "SYMPHONY_ISSUE_BODY_FILE=$CONTEXT_DIR/issue-body.md"
