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
  # Usage: plane_dump_comments OUTPUT_FILE [LIMIT]
  # Writes the most recent N comments (oldest → newest) to the output file as plain text.
  #
  # Failure semantics (PRO-24): the curl/jq pipeline writes to a tempfile first and only
  # atomically renames into place on success. A Plane API hiccup (transport error, error
  # JSON body that breaks `jq`) returns non-zero WITHOUT clobbering the previous file —
  # the calling hook can then `set -euo pipefail` and abort the attempt while leaving the
  # prior `.symphony/ticket-thread.md` intact for the next retry.
  local out="$1"
  local limit="${2:-50}"
  local tmp
  tmp=$(mktemp "${out}.XXXXXX")

  if plane_api GET "/projects/$SYMPHONY_PROJECT_ID/work-items/$SYMPHONY_ISSUE_ID/comments/" \
    | jq -r --argjson limit "$limit" \
        '.results
         | sort_by(.created_at)
         | .[(-$limit):]
         | .[]
         | "[\(.created_at)] \(.actor_detail.display_name // "agent"): \(.comment_stripped)"' \
    > "$tmp"; then
    mv "$tmp" "$out"
  else
    rm -f "$tmp"
    return 1
  fi
}

plane_dump_issue_body() {
  # Usage: plane_dump_issue_body OUTPUT_FILE
  # Writes the issue body (description_stripped, falling back to description_html) to the
  # output file. Same atomic-rename failure semantics as plane_dump_comments — a Plane API
  # error leaves the previous file intact and returns non-zero.
  local out="$1"
  local tmp
  tmp=$(mktemp "${out}.XXXXXX")

  if plane_api GET "/projects/$SYMPHONY_PROJECT_ID/work-items/$SYMPHONY_ISSUE_ID/" \
    | jq -r '.description_stripped // .description_html // ""' \
    > "$tmp"; then
    mv "$tmp" "$out"
  else
    rm -f "$tmp"
    return 1
  fi
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
