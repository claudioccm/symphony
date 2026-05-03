# symphony-hooks

Bash lifecycle hooks that wire Symphony's workspace events to Plane (issues, comments,
state). Copied from the upstream source kit at
`~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/{hooks,lib,workflow}`
and adapted for this fork's `WORKFLOW.md`. Tracking ticket: PRO-24.

## Layout

```
symphony-hooks/
  hooks/
    after_create.sh    runs once per new workspace; primes ticket-thread.md + issue-body.md
    before_run.sh      runs before each attempt; refreshes the same files (load-bearing)
    after_run.sh       runs after each attempt; appends a telemetry line to attempts.log
    before_remove.sh   runs before workspace cleanup; snapshots attempts.log and posts a final comment
  lib/
    plane.sh           shared curl/jq helpers used by hooks (sourced via ../lib/plane.sh)
    symphony-env.sh    env shim that derives SYMPHONY_* vars upstream Symphony does not inject
```

## Install

The fork keeps the canonical copy at `symphony-hooks/`. Symphony reads them by absolute
path, so the operator copies the directory to a stable host location that does not move
when worktrees come and go.

```bash
cp -R symphony-hooks ~/.claude/symphony-hooks
chmod +x ~/.claude/symphony-hooks/hooks/*.sh ~/.claude/symphony-hooks/lib/*.sh
```

After install, the host layout mirrors the fork layout:

```
~/.claude/symphony-hooks/
  hooks/{after_create,before_run,after_run,before_remove}.sh
  lib/{plane.sh,symphony-env.sh}
```

The fork's `WORKFLOW.md` references the four hooks via absolute paths under
`~/.claude/symphony-hooks/`, each invoked through `lib/symphony-env.sh`.

## Per-hook responsibilities

- **after_create.sh** — runs once when Symphony allocates a workspace for a card. Dumps
  the most recent 50 Plane comments into `$SYMPHONY_WORKSPACE/.symphony/ticket-thread.md`
  (one tab-separated line per comment) and the issue description into `issue-body.md`.
  Failure aborts the run; if Plane returns an error the workspace is rejected.
- **before_run.sh** — runs before every attempt. Refreshes `ticket-thread.md` and
  `issue-body.md` against live Plane state. **Load-bearing for the "Needs Decision"
  pause/resume protocol** — the agent prompt template includes ticket-thread.md verbatim
  to surface human responses across attempt boundaries.
- **after_run.sh** — runs after each attempt. Appends a single tab-separated telemetry
  line to `$SYMPHONY_WORKSPACE/.symphony/attempts.log` of the form
  `<iso8601>\tattempt=<N>\tresult=<status>`. Failures are logged but do not gate
  progress.
- **before_remove.sh** — runs once before workspace removal (only on terminal-state
  transitions: `Done`, `Cancelled`, `Duplicate`). Snapshots `attempts.log` to
  `~/.symphony/snapshots/<identifier>/` and posts a final HTML "Workspace cleaned up"
  comment to the Plane card. Failures are tolerated.

## Required environment

`lib/plane.sh` (and indirectly every hook) requires:

- `PLANE_API_KEY` — Plane personal access token
- `PLANE_WORKSPACE_SLUG` — workspace identifier from the Plane URL (e.g. `ccm-design`)
- `PLANE_PROJECT_IDENTIFIER` — project prefix in the `<PREFIX>-<seq>` ticket id (e.g. `PRO`)
- `PLANE_BASE_URL` — defaults to `https://api.plane.so`; override for self-hosted Plane

The `lib/symphony-env.sh` shim derives the per-attempt context (workspace path, issue
identifier, project UUID, issue UUID) from `$PWD` and the Plane API at hook invocation
time. Upstream Symphony does not inject `SYMPHONY_ISSUE_ID` / `SYMPHONY_PROJECT_ID`
itself, so the shim makes one HTTP call per cold cache to resolve them, then caches under
`$TMPDIR/symphony-hook-cache/`.

## Synthetic hook firing test

The hooks can be exercised against a real Plane card without booting Symphony — useful
for verifying the install end-to-end before wiring `WORKFLOW.md`.

```bash
export SYMPHONY_ISSUE_ID=23b5c4c0-d7d8-4114-af57-93e4b0b0e402  # PRO-23 UUID
export SYMPHONY_ISSUE_IDENTIFIER=PRO-23
export SYMPHONY_PROJECT_ID=bb1fe7b3-946c-488a-b4f8-a11e0d346c77
export SYMPHONY_WORKSPACE=$(mktemp -d)
export SYMPHONY_BRANCH=test-branch
export SYMPHONY_ATTEMPT=1

bash ~/.claude/symphony-hooks/hooks/after_create.sh
test -s "$SYMPHONY_WORKSPACE/.symphony/ticket-thread.md" || exit 1
test -s "$SYMPHONY_WORKSPACE/.symphony/issue-body.md"    || exit 1
echo "after_create OK"

bash ~/.claude/symphony-hooks/hooks/before_run.sh
echo "before_run OK"
```

Both hooks should exit zero and leave non-empty `.symphony/ticket-thread.md` and
`.symphony/issue-body.md` files in the temp workspace. PRO-23 has many existing comments,
so the line count of `ticket-thread.md` should be greater than zero.

## Pointer to the source kit

Full integration context, the install/wiring story for the Symphony fork, and the Plane
API quirks the hooks already work around live in
`~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/README.md`. That doc
covers Phase 2 (webhook-driven invalidation) and the behavioral notes for module
filtering, comment HTML shape, and relations endpoints — none of which the hooks need to
care about, but worth reading once to understand why the helpers are shaped the way they
are.
