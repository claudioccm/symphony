#!/usr/bin/env bash
# Symphony hook: before_remove
# Runs before workspace cleanup. Failures are ignored.
#
# Workspace cleanup happens when the issue reaches a terminal state (Done/Cancelled/Duplicate).
# Use this hook to:
#   1. Post a final summary comment to the Plane card.
#   2. Snapshot any local artifacts you want to keep (the worktree is about to be deleted).

set -euo pipefail
source "$(dirname "$0")/../lib/plane.sh"

# Snapshot the attempts log into a long-lived location, so per-card history survives
# workspace removal. Adjust the destination to taste.
SNAPSHOT_DIR="${SYMPHONY_SNAPSHOT_DIR:-$HOME/.symphony/snapshots}"
mkdir -p "$SNAPSHOT_DIR/$SYMPHONY_ISSUE_IDENTIFIER"

if [ -f "$SYMPHONY_WORKSPACE/.symphony/attempts.log" ]; then
  cp "$SYMPHONY_WORKSPACE/.symphony/attempts.log" \
     "$SNAPSHOT_DIR/$SYMPHONY_ISSUE_IDENTIFIER/attempts.log"
fi

# Post a single final comment summarizing the workspace lifecycle. The lfg-symphony command
# already posts a "🚀 MERGED TO DEV" comment on the success path; this is just the cleanup
# acknowledgement.
COMMENT_HTML=$(md_to_html "🧹 Workspace cleaned up.

Attempts: $SYMPHONY_ATTEMPT
Snapshot: $SNAPSHOT_DIR/$SYMPHONY_ISSUE_IDENTIFIER/")

plane_post_comment "$COMMENT_HTML" || true
