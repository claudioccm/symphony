#!/usr/bin/env bash
# Shared bash helpers for Plane REST calls used by Symphony lifecycle hooks.
# Source this file from each hook script: `source "$(dirname "$0")/../lib/plane.sh"`

set -euo pipefail

: "${PLANE_API_KEY:?PLANE_API_KEY not set}"
: "${PLANE_WORKSPACE_SLUG:?PLANE_WORKSPACE_SLUG not set}"
: "${PLANE_BASE_URL:=https://api.plane.so}"

# All Symphony lifecycle hooks receive these env vars:
#   SYMPHONY_ISSUE_ID         — Plane work-item UUID
#   SYMPHONY_ISSUE_IDENTIFIER — e.g. CCM-103
#   SYMPHONY_PROJECT_ID       — Plane project UUID (set by orchestrator after first lookup)
#   SYMPHONY_WORKSPACE        — absolute path to per-card git worktree
#   SYMPHONY_BRANCH           — feature branch name
#   SYMPHONY_ATTEMPT          — attempt counter

plane_api() {
  # Usage: plane_api METHOD PATH [JSON_BODY]
  local method="$1"
  local path="$2"
  local body="${3:-}"

  local url="$PLANE_BASE_URL/api/v1/workspaces/$PLANE_WORKSPACE_SLUG$path"

  if [ -n "$body" ]; then
    curl -sS -X "$method" \
      -H "X-API-Key: $PLANE_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$url"
  else
    curl -sS -X "$method" \
      -H "X-API-Key: $PLANE_API_KEY" \
      "$url"
  fi
}

plane_post_comment() {
  # Usage: plane_post_comment "<html body>"
  local html="$1"
  local body
  body=$(jq -n --arg html "$html" '{comment_html: $html}')
  plane_api POST \
    "/projects/$SYMPHONY_PROJECT_ID/work-items/$SYMPHONY_ISSUE_ID/comments/" \
    "$body" >/dev/null
}

plane_set_state_by_id() {
  # Usage: plane_set_state_by_id "<state-uuid>"
  local state_id="$1"
  local body
  body=$(jq -n --arg s "$state_id" '{state: $s}')
  plane_api PATCH \
    "/projects/$SYMPHONY_PROJECT_ID/work-items/$SYMPHONY_ISSUE_ID/" \
    "$body" >/dev/null
}

plane_state_id_by_name() {
  # Usage: plane_state_id_by_name "<state-name>"
  local name="$1"
  plane_api GET "/projects/$SYMPHONY_PROJECT_ID/states/" \
    | jq -r --arg n "$name" '.results[] | select(.name == $n) | .id'
}

plane_dump_comments() {
  # Usage: plane_dump_comments OUTPUT_FILE
  # Writes the most recent N comments (oldest → newest) to the output file as plain text.
  local out="$1"
  local limit="${2:-50}"

  plane_api GET "/projects/$SYMPHONY_PROJECT_ID/work-items/$SYMPHONY_ISSUE_ID/comments/" \
    | jq -r --argjson limit "$limit" \
        '.results
         | sort_by(.created_at)
         | .[(-$limit):]
         | .[]
         | "[\(.created_at)] \(.actor_detail.display_name // "agent"): \(.comment_stripped)"' \
    > "$out"
}

# Convenience: convert markdown body to a minimal HTML body for Plane.
# Identical logic to the Elixir adapter's markdown_to_html/1, just enough for paragraphs.
md_to_html() {
  local md="$1"
  python3 - <<'PY' "$md"
import sys, html
md = sys.argv[1]
blocks = [b for b in md.split("\n\n") if b.strip()]
out = []
for b in blocks:
    if b.startswith("```"):
        inner = b.strip("`").lstrip("\n")
        out.append(f"<pre><code>{html.escape(inner)}</code></pre>")
    else:
        out.append("<p>" + html.escape(b).replace("\n", "<br/>") + "</p>")
print("\n".join(out))
PY
}
