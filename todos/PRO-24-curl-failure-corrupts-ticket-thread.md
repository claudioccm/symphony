---
severity: P1
autofix_class: gated_auto
owner: downstream-resolver
file: symphony-hooks/lib/plane.sh
line: 73
ticket: PRO-24
status: resolved
resolved_in: feature/PRO-24-lifecycle-hooks
---

## Resolution (Step 4)

Fixed in `symphony-hooks/lib/plane.sh` and the two hook scripts that consumed the
issue-body endpoint inline (`after_create.sh`, `before_run.sh`).

### Changes
- `plane_dump_comments` now writes to a `mktemp`-allocated tempfile and only `mv`s
  into the destination on success of the curl→jq pipeline. On failure it `rm -f`s
  the tempfile and `return 1`s. The previous file is preserved.
- Added a sibling helper `plane_dump_issue_body OUTPUT_FILE` with identical
  semantics, factoring the duplicated `description_stripped // .description_html`
  logic out of the hooks.
- `after_create.sh:19-22` and `before_run.sh:17-19` switched from the inline
  `plane_api | jq > "$file"` (vulnerable to the same truncate-then-fail) to the
  new helper. Justified by the constraint that hook scripts can change when
  needed to surface the new error path.

### Tests run

1. **Happy path (synthetic hook test from the spec):**
   `after_create.sh` against PRO-23, fresh workspace → exit 0,
   `.symphony/ticket-thread.md` is non-empty.
2. **Corruption test, transport failure:**
   `PLANE_BASE_URL=http://127.0.0.1:1` (closed port) on top of a sentinel-populated
   `ticket-thread.md` → curl exits 7, hook returns 1, sentinel preserved verbatim,
   no leftover `*.XXXXXX` tempfiles.
3. **Corruption test, bad auth (the exact scenario in this todo):**
   `PLANE_API_KEY=invalid-key-xyz` → Plane returns a 4xx error JSON, jq fails on
   `Cannot iterate over null`, hook returns 1, sentinel preserved, no leftover
   tempfiles.

### Host install
`~/.claude/symphony-hooks/lib/plane.sh`, `hooks/after_create.sh`, and
`hooks/before_run.sh` synced via `cp`.

### Failure-mode contract chosen
Option (a) from the todo: preserve the previous file AND fail the attempt
non-zero. The hook now propagates the curl/jq failure up so Symphony can retry,
while the prior `.symphony/ticket-thread.md` survives intact for the next
attempt's "Needs Decision" pause/resume context.

# `plane_dump_comments` can leave `.symphony/ticket-thread.md` empty on Plane API errors

## Problem

`plane_dump_comments` (`symphony-hooks/lib/plane.sh:67-81`) writes via shell redirection
`> "$out"`, which truncates the destination file before the pipeline runs. Because
`curl -sS` returns exit 0 for 4xx/5xx HTTP responses (it only fails on transport errors),
a Plane API hiccup that returns an error JSON body goes through this path:

```
curl -sS ... | jq -r '.results | sort_by(...) | .[(-$limit):] | .[] | ...' > "$out"
```

`jq` then fails (the error JSON has no `.results`). With `set -euo pipefail` in the calling
hook, the script aborts — good, fails closed. But the redirection has already truncated
the output file. So a previously-good `.symphony/ticket-thread.md` gets replaced with an
empty file before the hook exits. On the next attempt, `before_run.sh` will rewrite the
file from a fresh API call, but if Plane is *still* down, the agent prompt template
(`{% include_file ".symphony/ticket-thread.md" %}`) will surface an empty thread to the
agent and the "Needs Decision" pause/resume protocol silently drops the human's reply.

This is exactly the failure mode the orchestrator flagged: "Plane API hiccups must not
silently corrupt `.symphony/*.md`."

## Suggested fix

Buffer the curl/jq output to a temp file and atomic-rename only on success:

```bash
plane_dump_comments() {
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
```

The same pattern applies to the `description_stripped // .description_html` redirection
in `after_create.sh:20-22` and `before_run.sh:17-19`. Either factor a helper into
`lib/plane.sh` (`plane_dump_issue_body`) or inline the same temp-file dance in each hook.

## Why this is `gated_auto`, not `safe_auto`

- The implementation plan explicitly says the hook scripts are pre-drafted and copied
  verbatim ("Do not edit content" — U1 of the plan).
- Adding error handling changes the hook's failure-mode contract. A reviewer should
  decide whether failed Plane calls should:
    (a) preserve the previous file (this proposal), or
    (b) fail the attempt outright (current behavior with set -euo pipefail), or
    (c) write a sentinel like `{"error": "Plane API unreachable"}` so the agent prompt
        surfaces the failure instead of silently presenting stale-or-empty context.
- The fix should land alongside a synthetic-failure test (`PLANE_API_KEY=invalid bash
  ~/.claude/symphony-hooks/hooks/before_run.sh` with a pre-existing `ticket-thread.md`
  in place — verify it survives).

## Verification when fixing

1. Pre-populate `.symphony/ticket-thread.md` with a known sentinel.
2. Run `before_run.sh` with `PLANE_API_KEY=invalid` (or block port 443).
3. Confirm the hook exits non-zero (fails the attempt) AND the original sentinel is
   still on disk.
4. Then unset the bad env, run again, confirm the file is correctly refreshed.
