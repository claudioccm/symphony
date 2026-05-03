#!/usr/bin/env bash
# Symphony hook env shim.
#
# Upstream Symphony (openai/symphony) does NOT inject SYMPHONY_* env vars when
# invoking lifecycle hooks — it just runs `sh -lc <command>` with the workspace
# as cwd. The hook scripts in `../hooks/` were drafted against a Symphony fork
# that DOES inject SYMPHONY_ISSUE_ID, SYMPHONY_PROJECT_ID, etc.
#
# This shim derives the missing env from:
#   - $PWD                          → SYMPHONY_WORKSPACE
#   - basename $PWD                 → SYMPHONY_ISSUE_IDENTIFIER (e.g. PRO-25)
#   - PLANE_PROJECT_IDENTIFIER env  → resolves to SYMPHONY_PROJECT_ID via Plane API
#   - SYMPHONY_ISSUE_IDENTIFIER     → resolves to SYMPHONY_ISSUE_ID via Plane API
#
# Then it execs the wrapped hook script. Usage from WORKFLOW.md:
#
#   hooks:
#     after_create: /abs/path/to/symphony-hooks/lib/symphony-env.sh /abs/path/to/symphony-hooks/hooks/after_create.sh
#
# This file is the only delta required to bridge the upstream Symphony hook
# contract to the source-kit hooks. Once Symphony grows native env injection
# (or the kit is rewritten to read $PWD directly), this shim can be retired.

set -euo pipefail

: "${PLANE_API_KEY:?PLANE_API_KEY not set}"
: "${PLANE_WORKSPACE_SLUG:?PLANE_WORKSPACE_SLUG not set}"
: "${PLANE_PROJECT_IDENTIFIER:?PLANE_PROJECT_IDENTIFIER not set}"
: "${PLANE_BASE_URL:=https://api.plane.so}"

if [ "$#" -lt 1 ]; then
  echo "symphony-env.sh: missing wrapped hook path" >&2
  exit 2
fi

WRAPPED_HOOK="$1"
shift

# Derive workspace + identifier from cwd (Symphony cd's into workspace before invoking).
export SYMPHONY_WORKSPACE="${SYMPHONY_WORKSPACE:-$PWD}"
export SYMPHONY_ISSUE_IDENTIFIER="${SYMPHONY_ISSUE_IDENTIFIER:-$(basename "$SYMPHONY_WORKSPACE")}"
export SYMPHONY_BRANCH="${SYMPHONY_BRANCH:-symphony/$SYMPHONY_ISSUE_IDENTIFIER}"
export SYMPHONY_ATTEMPT="${SYMPHONY_ATTEMPT:-1}"

CACHE_DIR="${SYMPHONY_HOOK_CACHE_DIR:-${TMPDIR:-/tmp}/symphony-hook-cache}"
mkdir -p "$CACHE_DIR"
PROJECT_CACHE="$CACHE_DIR/project_id_${PLANE_WORKSPACE_SLUG}_${PLANE_PROJECT_IDENTIFIER}"

# Resolve SYMPHONY_PROJECT_ID once and cache.
if [ -z "${SYMPHONY_PROJECT_ID:-}" ]; then
  if [ -s "$PROJECT_CACHE" ]; then
    SYMPHONY_PROJECT_ID=$(cat "$PROJECT_CACHE")
  else
    SYMPHONY_PROJECT_ID=$(curl -sS \
      -H "X-API-Key: $PLANE_API_KEY" \
      "$PLANE_BASE_URL/api/v1/workspaces/$PLANE_WORKSPACE_SLUG/projects/" \
      | jq -r --arg ident "$PLANE_PROJECT_IDENTIFIER" \
          '.results[] | select(.identifier == $ident) | .id')
    if [ -z "$SYMPHONY_PROJECT_ID" ] || [ "$SYMPHONY_PROJECT_ID" = "null" ]; then
      echo "symphony-env.sh: cannot resolve project '$PLANE_PROJECT_IDENTIFIER' in workspace '$PLANE_WORKSPACE_SLUG'" >&2
      exit 3
    fi
    printf '%s' "$SYMPHONY_PROJECT_ID" > "$PROJECT_CACHE"
  fi
  export SYMPHONY_PROJECT_ID
fi

# Resolve SYMPHONY_ISSUE_ID via the identifier's sequence_id.
# Identifier shape: <prefix>-<seq>, e.g. PRO-25 → seq=25.
if [ -z "${SYMPHONY_ISSUE_ID:-}" ]; then
  SEQ="${SYMPHONY_ISSUE_IDENTIFIER##*-}"
  ISSUE_CACHE="$CACHE_DIR/issue_id_${PLANE_WORKSPACE_SLUG}_${SYMPHONY_PROJECT_ID}_${SEQ}"
  if [ -s "$ISSUE_CACHE" ]; then
    SYMPHONY_ISSUE_ID=$(cat "$ISSUE_CACHE")
  else
    # Plane's bare work-items list returns project-wide results; we filter by sequence_id.
    SYMPHONY_ISSUE_ID=$(curl -sS \
      -H "X-API-Key: $PLANE_API_KEY" \
      "$PLANE_BASE_URL/api/v1/workspaces/$PLANE_WORKSPACE_SLUG/projects/$SYMPHONY_PROJECT_ID/work-items/?per_page=200" \
      | jq -r --argjson seq "$SEQ" \
          '.results[] | select(.sequence_id == $seq) | .id' \
      | head -n1)
    if [ -z "$SYMPHONY_ISSUE_ID" ] || [ "$SYMPHONY_ISSUE_ID" = "null" ]; then
      echo "symphony-env.sh: cannot resolve issue '$SYMPHONY_ISSUE_IDENTIFIER' (seq=$SEQ) in project $SYMPHONY_PROJECT_ID" >&2
      exit 4
    fi
    printf '%s' "$SYMPHONY_ISSUE_ID" > "$ISSUE_CACHE"
  fi
  export SYMPHONY_ISSUE_ID
fi

exec "$WRAPPED_HOOK" "$@"
