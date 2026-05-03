---
title: "feat: Symphony lifecycle hooks + WORKFLOW.md (Plane integration)"
type: feat
status: active
date: 2026-05-02
---

# feat: Symphony lifecycle hooks + WORKFLOW.md (Plane integration)

## Summary

Wire four pre-drafted bash lifecycle hooks (`after_create.sh`, `before_run.sh`, `after_run.sh`, `before_remove.sh`) plus a shared `lib/plane.sh` helper to Symphony's hook system, install a `WORKFLOW.md` that points Symphony at those hooks, and verify the integration end-to-end against the Symphony module in the `PRO` Plane project. The codex command is intentionally a no-op `echo` for this card — PRO-25 owns the full `/lfg-symphony` pipeline. The load-bearing behavior is `before_run.sh` refreshing `.symphony/ticket-thread.md` from Plane comments at the start of every attempt; that file is what the agent prompt template includes to recover context across the "Needs Decision" pause/resume protocol.

---

## Problem Frame

PRO-23 landed the Plane tracker adapter (`SymphonyElixir.Plane.{Adapter,Client,Issue}` at `elixir/lib/symphony_elixir/plane/`), so Symphony can now poll Plane, normalize work items, post comments, and move states. What's still missing is the hook layer that runs on each lifecycle transition (workspace create, attempt start, attempt end, workspace remove) — without it, the agent prompt has no recent ticket-thread context, telemetry isn't written, and there's no acknowledgement comment when a card reaches a terminal state. Until the hooks + WORKFLOW.md ship, Symphony cannot drive a Plane card through even a no-op attempt loop, blocking PRO-25 from picking up where this card leaves off. The hook scripts and helper library are already drafted in `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/`; the work here is integration, hosting layout, and verification — not authorship.

---

## Requirements

- R1. Install the four hook scripts (`after_create.sh`, `before_run.sh`, `after_run.sh`, `before_remove.sh`) and the shared `lib/plane.sh` at a stable host path so Symphony can invoke them across worktrees and shells.
- R2. Preserve the `hooks/` + `lib/` sibling layout at the host install path so each hook's `source "$(dirname "$0")/../lib/plane.sh"` resolves correctly without edits.
- R3. Make all `.sh` files executable (`chmod +x`) at the host install path.
- R4. Commit the hook scripts and helper library to this Symphony fork on the `feature/PRO-24-lifecycle-hooks` branch as the source of truth, with a layout that mirrors the host install path so an installer can copy or symlink without renaming.
- R5. Install a `WORKFLOW.md` at the repo root of the Symphony-managed project with `hooks.*` paths pointing at absolute filesystem locations under the host install directory (`~/.claude/symphony-hooks/hooks/*.sh`). The codex command is `echo` (no-op) for this card.
- R6. The synthetic hook firing test against PRO-23 (UUID `23b5c4c0-d7d8-4114-af57-93e4b0b0e402`) succeeds: `after_create.sh` produces a non-empty `.symphony/ticket-thread.md` and `.symphony/issue-body.md`, and `before_run.sh` rewrites both without error.
- R7. `.symphony/ticket-thread.md` written by the synthetic test contains at least one line per existing Plane comment on PRO-23 (format: `[<created_at>] <actor>: <body>`).
- R8. Booting Symphony with this `WORKFLOW.md` (`cd elixir && mix symphony.run --workflow path/to/WORKFLOW.md`) reports exactly the 3 Symphony-module cards (PRO-23, PRO-24, PRO-25) as candidates and fires `after_create` against at least one of them, populating `.symphony/ticket-thread.md` in the agent's workspace.
- R9. No state changes occur during verification — the codex command is `echo`, so Symphony spins up workspaces and fires hooks but never moves cards or posts non-cleanup comments. (The `before_remove.sh` cleanup comment only fires when a card reaches a terminal state during the test, which is not expected since `echo` doesn't progress cards.)
- R10. A PR is opened against the fork's `dev` branch (per user CLAUDE.md: "worktree → PR → merge to dev") titled `feat(symphony): add Plane lifecycle hooks + workflow`, summarizing each hook's responsibility and the synthetic-test command.

---

## Scope Boundaries

- The `/lfg-symphony` Claude Code slash command and the full Compound Engineering pipeline it drives — owned by PRO-25.
- Auto-merge logic, PR open/merge automation, and the Needs Decision pause/resume control flow inside the agent — owned by PRO-25.
- Webhook-driven invalidation of polling — explicit non-goal (Phase 2 in `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/docs/PHASE2-WEBHOOKS.md`).
- Multi-card concurrency stress testing — explicit non-goal; this card validates against a single live invocation only.
- Authoring or rewriting the hook scripts themselves — they are pre-drafted, this work is integration and hosting.
- Modifying any Elixir code in `elixir/lib/symphony_elixir/` — the adapter wiring is complete from PRO-23.
- Custom-property support, pagination, `blocked_by` resolution, 429 retry — out of scope for hooks (and already deferred from PRO-23).
- Editing the agent prompt template inside `WORKFLOW.md` beyond the hook path adjustments — the prompt is fine as drafted.

### Deferred to Follow-Up Work

- Replacing the `echo` codex command with the real `/lfg-symphony` invocation (`claude -p /lfg-symphony --dangerously-skip-permissions`) — PRO-25.
- An installer script that copies or symlinks `symphony-hooks/` from the fork to `~/.claude/symphony-hooks/` — useful but not required to land this card; documented as a manual step in the PR body.
- Webhook receiver for sub-poll-interval Needs Decision resume — Phase 2.
- Snapshot retention policy under `~/.symphony/snapshots/<identifier>/` — `before_remove.sh` writes there, but pruning is left to the operator.

---

## Context & Research

### Relevant Code and Patterns

- `elixir/lib/symphony_elixir/plane/adapter.ex` — already in place from PRO-23. The hooks do not call into the adapter; they hit Plane's REST API directly via `lib/plane.sh`. Knowing the adapter exists matters only because Symphony's startup must succeed before hooks fire.
- `elixir/lib/symphony_elixir/plane/client.ex` — sibling reference; the bash `lib/plane.sh` mirrors its endpoint shapes (work-items, comments, states) for parity.
- The `hooks` block schema in `WORKFLOW.md` (Symphony framework) — keys: `after_create`, `before_run`, `after_run`, `before_remove`, `timeout_ms`. Paths can be relative to `WORKFLOW.md` or absolute. We use absolute for host-install stability.
- `tracker:` block in `WORKFLOW.md` — `kind: plane`, `active_states: [Todo, "In Progress"]`, `terminal_states: [Done, Cancelled, Duplicate]`. Drives candidate fetch.
- `agent:` block — `max_concurrent_agents: 4`, with per-state overrides. Inherited verbatim from the source kit.
- `codex:` block — `command`, `args`, `approval_policy`, `thread_sandbox`. We override `command` to `echo` and clear `args` for this card.

### Pre-drafted source kit (to be copied/installed)

- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/hooks/after_create.sh` — 27 lines; runs once per workspace creation. Dumps comments via `plane_dump_comments` and the issue description via `plane_api GET .../work-items/<id>/`. Failure here aborts the run.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/hooks/before_run.sh` — 24 lines; **load-bearing**. Refreshes `ticket-thread.md` and `issue-body.md` before each attempt. The agent prompt's `{% include_file ".symphony/ticket-thread.md" %}` directive depends on this file existing and being current.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/hooks/after_run.sh` — 23 lines; appends a tab-separated telemetry line (`<iso8601>\tattempt=N\tresult=<status>`) to `.symphony/attempts.log`. Failures are logged but ignored.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/hooks/before_remove.sh` — 32 lines; snapshots `attempts.log` to `~/.symphony/snapshots/<identifier>/` and posts a final HTML "Workspace cleaned up" comment via `plane_post_comment`. Failures are tolerated (`|| true`).
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/lib/plane.sh` — 101 lines; shared helpers. Sourced by every hook via the relative path `"$(dirname "$0")/../lib/plane.sh"` — so the `hooks/` ↔ `lib/` sibling layout is structural and must be preserved at every install location. Helpers: `plane_api`, `plane_post_comment`, `plane_set_state_by_id`, `plane_state_id_by_name`, `plane_dump_comments`, `md_to_html`. Reads env: `PLANE_API_KEY`, `PLANE_WORKSPACE_SLUG`, `PLANE_BASE_URL` (default `https://api.plane.so`).
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/workflow/WORKFLOW.md` — 88 lines. Two parts: YAML frontmatter (tracker, agent, hooks, codex) and a Liquid prompt body that pulls `issue.identifier`, `issue.title`, `issue.url`, `workspace.path`, `workspace.branch`, `attempt`, `issue.description`, and includes `.symphony/ticket-thread.md`. We adjust `hooks.*` to absolute paths and `codex.command` to `echo`.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/README.md` — 186 lines; full integration context. Lines 65–73 cover hook copy + chmod. Lines 133–185 cover Plane module + relations API quirks (relevant to PRO-23/25, not directly to this card; preserved for ambient context).

### Plane API quirks the hooks already account for

- **Module filtering doesn't work on `/work-items/`**: invisible to the hook layer. Hooks only query single-issue endpoints — `/projects/<pid>/work-items/<wid>/` and `/projects/<pid>/work-items/<wid>/comments/` — never list-all-issues. So the quirk has no effect here.
- **Comments are HTML-only**: `lib/plane.sh` includes `md_to_html()` (a tiny Python3 helper that wraps paragraphs in `<p>...</p>` and code fences in `<pre><code>...</code></pre>`). `before_remove.sh` uses it on the cleanup comment body. `plane_post_comment` posts the resulting `comment_html` payload.
- **Comment fetch endpoint**: `GET /projects/<pid>/work-items/<wid>/comments/`. `plane_dump_comments` sorts results by `created_at` and trims to the most recent N (default 50) — Plane returns oldest-first order in `.results` already, but the explicit sort guards against shape drift.

### Institutional Learnings

- None applicable from `docs/solutions/` for this hook layer (the directory exists from PRO-23 but contains no entries relevant to bash hooks or Symphony lifecycle plumbing yet).

### External References

- Plane REST API: `https://api.plane.so/api/v1/workspaces/<slug>/projects/<id>/...`. Authoritative quirks documented at `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/README.md` lines 133–185.
- The user-level `plane-api` skill is available for ad-hoc Plane REST calls if questions arise during implementation.
- Symphony framework hook schema and env vars exposed to hooks (`SYMPHONY_ISSUE_ID`, `SYMPHONY_ISSUE_IDENTIFIER`, `SYMPHONY_PROJECT_ID`, `SYMPHONY_WORKSPACE`, `SYMPHONY_BRANCH`, `SYMPHONY_ATTEMPT`, `SYMPHONY_ATTEMPT_RESULT`) — documented inline in `lib/plane.sh` lines 11–17 and used throughout the hooks.

---

## Key Technical Decisions

- **Fork-side source of truth: `symphony-hooks/` at the repo root.** Three options were considered (see Alternative Approaches Considered below). Picked because (a) it mirrors the host install layout exactly (`symphony-hooks/hooks/`, `symphony-hooks/lib/`) so an installer is a one-liner `cp -R symphony-hooks ~/.claude/`; (b) it makes the hooks discoverable at the top of the fork without burying them under `extras/` (which connotes optional-and-unsupported); (c) it keeps the Elixir tree (`elixir/`, `docs/`, etc.) cleanly separated from shell tooling. The PR body documents the install command for users.
- **Host install path: `~/.claude/symphony-hooks/`.** Stable across worktrees and shells, namespaced under `~/.claude/` (consistent with the user-level CLAUDE.md ecosystem of slash commands and global configs), and not tied to any single repo path. Symphony's `WORKFLOW.md` references absolute paths under this directory so the workflow file is portable across repos.
- **Absolute paths in `WORKFLOW.md` `hooks.*`.** The drafted `WORKFLOW.md` uses relative paths (`./hooks/after_create.sh`). We rewrite to absolute (`/Users/claudiomendonca/.claude/symphony-hooks/hooks/after_create.sh` — but stored as `~`-prefixed in the source-of-truth fork copy and expanded at install time, OR stored as fully expanded for the developer machine). **Decision**: store fully-expanded absolute paths (`/Users/claudiomendonca/.claude/symphony-hooks/...`) in the committed WORKFLOW.md for now, since this fork is single-developer at this stage and the path is stable. Document in the PR body that future multi-machine operators must re-edit the WORKFLOW.md or template via env substitution.
- **Codex command is `echo` for this card.** No `-p`, no `--dangerously-skip-permissions`, no args. Symphony will spawn the codex process per attempt; it'll print whatever Symphony pipes to stdin (or no-op output) and exit zero. This produces zero state changes on Plane cards while still exercising the full hook lifecycle. PRO-25 swaps `command` to `claude` and restores the args block.
- **WORKFLOW.md location for Symphony to manage.** Symphony manages a *target* repo, not its own fork. The drafted README assumes the operator places WORKFLOW.md at the root of the repo Symphony will work in. For this card's verification, we use the fork itself as the managed repo (it has the 3 Symphony-module cards as its tickets, and the `dev`/`main` branch flow works the same). So WORKFLOW.md goes at the **fork repo root** (`/Users/claudiomendonca/Documents/GitHub/symphony-wt/PRO-24/WORKFLOW.md`) and is committed alongside the hooks. PRO-25 may relocate it if the operator chooses a different managed repo.
- **No installer script in this card.** A `bin/install-symphony-hooks.sh` would be nice but is out of scope (deferred). The PR body documents the manual `cp -R symphony-hooks ~/.claude/symphony-hooks && chmod +x ~/.claude/symphony-hooks/hooks/*.sh` recipe.
- **Synthetic test runs from a `mktemp -d` workspace, not the worktree.** `SYMPHONY_WORKSPACE=$(mktemp -d)` keeps the test hermetic and prevents `.symphony/` directory residue in the fork. The Symphony boot test (step 6) uses Symphony's own workspace allocation under `/tmp/symphony-*`.
- **`chmod +x` is applied at both source-of-truth (in the fork) and host install path.** Git preserves the executable bit on the source files, so an installer that does `cp -R` carries it through. Belt-and-suspenders: the install command in the PR body re-runs `chmod +x` defensively.

---

## Open Questions

### Resolved During Planning

- **Where in the fork should the hooks live?** — `symphony-hooks/` at the repo root, mirroring host install layout. Rationale in Key Technical Decisions and Alternative Approaches Considered.
- **Should the codex command be `echo` with args, or just `echo` no-op?** — Just `command: echo` with no `args:` block (or empty list). Anything more starts to look like real codex behavior; we want the cleanest possible no-op so the verification is unambiguous about which side effects come from hooks vs. from codex.
- **Does Symphony fire hooks against `Todo` cards or only `In Progress`?** — `active_states` in WORKFLOW.md includes both. The hook fires once per workspace creation regardless of which active state triggered it. So the test will see `after_create` on at least one of the 3 candidate cards even though they're all in `Todo` at plan-time.
- **Where does `.symphony/ticket-thread.md` live?** — Under `$SYMPHONY_WORKSPACE/.symphony/`, where `$SYMPHONY_WORKSPACE` is the per-card git worktree Symphony allocates. The hook creates `.symphony/` if missing.
- **Does the synthetic test need internet access / a valid `PLANE_API_KEY`?** — Yes. The hooks call live Plane endpoints. The user's shell already has the env loaded; the test inherits it. PRO-23 must be a real card in the live workspace (it is — UUID `23b5c4c0-d7d8-4114-af57-93e4b0b0e402`).
- **What happens if Plane returns zero comments for PRO-23?** — `plane_dump_comments` writes an empty file; both R6 (file exists, non-empty) and R7 (one line per comment) need to handle the edge case. R6 says "non-empty"; R7 is conditional on existing comments. **Resolution**: PRO-23 has been live for the duration of PRO-23's implementation and has at least the merge-acknowledgement comments, so the `> 0 comments` precondition holds. If somehow it doesn't, the implementer adds one comment manually before the test run (documented inline in the verification section).
- **Does `WORKFLOW.md` need to be in `.gitignore` or committed?** — Committed, per R4 + R5. It is part of the fork's tooling. No secrets — env vars are not embedded.

### Deferred to Implementation

- **Exact format of `attempts.log` after a real `echo`-only run** — Symphony may set `SYMPHONY_ATTEMPT_RESULT` to `succeeded`, `noop`, `unknown`, or some framework-specific status when codex is a literal `echo`. The hook handles `unknown` as the default. Implementer observes the actual value during the boot test and notes it in the PR body if it surfaces something interesting; no code change needed unless the value breaks the log format.
- **Whether Symphony's hook timeout (`timeout_ms: 60000`) is enough for `before_run` against a card with many comments** — `plane_dump_comments` makes one HTTP call per hook invocation, well under 60s for any realistic comment count. If it times out in practice, raise the limit; not expected.
- **Whether `before_remove.sh`'s comment posts during the boot test** — only if a card reaches a terminal state during the test. With codex as `echo`, no state transitions occur, so `before_remove` should not fire. If it does (e.g., human moves a card to Done mid-test), the cleanup comment is acceptable side effect; documented in PR body.

---

## Output Structure

```
symphony-hooks/                          (new — repo root, mirrors host install layout)
  hooks/
    after_create.sh                      (new — copied from extras/symphony-plane-ce/hooks/)
    before_run.sh                        (new)
    after_run.sh                         (new)
    before_remove.sh                     (new)
  lib/
    plane.sh                             (new — shared helpers, sourced via ../lib/plane.sh)
  README.md                              (new — install command + per-hook one-liners; small)
WORKFLOW.md                              (new — repo root; tracker/agent/hooks/codex config + Liquid prompt)
docs/
  plans/
    2026-05-02-002-feat-symphony-lifecycle-hooks-plan.md   (this file)
```

Host install path (not in the repo, set up by the implementer):

```
~/.claude/symphony-hooks/
  hooks/{after_create,before_run,after_run,before_remove}.sh
  lib/plane.sh
```

---

## Implementation Units

- U1. **Create `symphony-hooks/` at the fork root and copy hook sources verbatim**

**Goal:** Land the four hook scripts and the shared `lib/plane.sh` helper inside the fork at `symphony-hooks/`, preserving the `hooks/` ↔ `lib/` sibling layout and the executable bit.

**Requirements:** R1, R2, R3, R4

**Dependencies:** None

**Files:**
- Create: `symphony-hooks/hooks/after_create.sh`
- Create: `symphony-hooks/hooks/before_run.sh`
- Create: `symphony-hooks/hooks/after_run.sh`
- Create: `symphony-hooks/hooks/before_remove.sh`
- Create: `symphony-hooks/lib/plane.sh`

**Approach:**
- `mkdir -p symphony-hooks/hooks symphony-hooks/lib` from the worktree root.
- Copy each `.sh` file verbatim from `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/hooks/` and `.../lib/` into the corresponding subdirectory. Do not edit content.
- `chmod +x symphony-hooks/hooks/*.sh symphony-hooks/lib/*.sh`. Confirm the bit is set with `ls -l`.
- Sanity-check: each hook's `source "$(dirname "$0")/../lib/plane.sh"` resolves to `symphony-hooks/lib/plane.sh` after the copy.

**Patterns to follow:**
- Layout mirrors `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/{hooks,lib}/`. Same names, same structure. Do not invent a different layout — the relative source path inside the hooks depends on it.

**Test scenarios:**
- Test expectation: none — pure file copy with no behavioral change. Behavioral validation of the hooks themselves lands in U4 (synthetic test).

**Verification:**
- All five files exist at `symphony-hooks/{hooks,lib}/...` with executable bit set.
- `bash -n symphony-hooks/hooks/after_create.sh` (and the other three) report no syntax errors.
- `git diff --stat` against `main` shows five new files under `symphony-hooks/`.

---

- U2. **Install hooks at the host path `~/.claude/symphony-hooks/`**

**Goal:** Make the hooks executable from a stable, repo-independent host path so Symphony's `WORKFLOW.md` can reference them by absolute path.

**Requirements:** R1, R2, R3

**Dependencies:** U1

**Files:**
- (Host-side, not in repo): `~/.claude/symphony-hooks/hooks/{after_create,before_run,after_run,before_remove}.sh`
- (Host-side): `~/.claude/symphony-hooks/lib/plane.sh`

**Approach:**
- `mkdir -p ~/.claude/symphony-hooks` if missing.
- `cp -R symphony-hooks/hooks symphony-hooks/lib ~/.claude/symphony-hooks/`. Use `-R` to preserve directory structure.
- `chmod +x ~/.claude/symphony-hooks/hooks/*.sh ~/.claude/symphony-hooks/lib/*.sh`. (Defensive — `cp` should preserve the bit, but re-asserting is cheap.)
- Verify the relative `source` path resolves: `bash -n ~/.claude/symphony-hooks/hooks/after_create.sh` exits zero.

**Patterns to follow:**
- The user-level CLAUDE.md ecosystem (`~/.claude/` is the established namespace for slash commands, settings, and now hooks).

**Test scenarios:**
- Test expectation: none — host install is mechanical. Behavioral coverage in U4.

**Verification:**
- `ls -l ~/.claude/symphony-hooks/hooks/` shows four `.sh` files, all `-rwxr-xr-x` (or equivalent with executable bit).
- `ls -l ~/.claude/symphony-hooks/lib/plane.sh` shows the shared helper, executable.
- `bash -n` on each hook reports clean syntax.

---

- U3. **Author `WORKFLOW.md` at the fork repo root**

**Goal:** Provide a Symphony-readable workflow file that points at the host-installed hooks, declares the Plane tracker, sets the codex command to `echo` no-op, and includes the agent prompt template.

**Requirements:** R5

**Dependencies:** U2 (the hook paths must exist at the host install path so the WORKFLOW.md references resolve at boot).

**Files:**
- Create: `WORKFLOW.md` (at the fork repo root, not under `symphony-hooks/`)

**Approach:**
- Start from a verbatim copy of `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/workflow/WORKFLOW.md`.
- In the YAML frontmatter, edit `hooks.*` paths to absolute filesystem locations: `/Users/claudiomendonca/.claude/symphony-hooks/hooks/<hook>.sh` for each of the four hooks. Keep `timeout_ms: 60000` as drafted.
- In `codex:`, replace `command: claude` with `command: echo`. Remove or comment out the `args:` block (an `echo` invocation with `["-p", "/lfg-symphony", "--dangerously-skip-permissions"]` would still print those literal args — fine for verification but noisy; cleaner to omit the args entirely so the no-op is unambiguous).
- Leave `approval_policy: never`, `thread_sandbox: workspace_write` as drafted (they're irrelevant for `echo` but harmless).
- Leave the `tracker:`, `agent:`, and Liquid prompt body unchanged.
- Add a one-line comment at the top of the YAML noting that codex is intentionally `echo` for PRO-24 verification and is swapped to `claude` in PRO-25.

**Patterns to follow:**
- The drafted source `workflow/WORKFLOW.md` is the canonical shape. Only the deltas above are intentional changes; everything else is preserved.

**Test scenarios:**
- Test expectation: none for the file itself — it's config. Behavioral validation comes via U5 (Symphony boot test) which is what actually exercises this file.

**Verification:**
- `cat WORKFLOW.md` shows the four absolute hook paths, each pointing at an existing file from U2.
- `head WORKFLOW.md` shows YAML frontmatter starting with `---` and `tracker:` block within the first ~10 lines (sanity that frontmatter wasn't corrupted by the edit).
- A YAML linter (or `python3 -c "import yaml; yaml.safe_load(open('WORKFLOW.md').read().split('---')[1])"`) parses the frontmatter without error.

---

- U4. **Synthetic hook firing test against PRO-23**

**Goal:** Validate that `after_create.sh` and `before_run.sh` succeed against the live Plane API for a real card (PRO-23) in a hermetic temp workspace, before bringing Symphony into the loop.

**Requirements:** R6, R7

**Dependencies:** U2 (host-installed hooks must exist).

**Files:**
- (Test-only — no files created in the repo. Optionally a small `symphony-hooks/test/synthetic-fire.sh` wrapper script if the implementer wants to canonicalize the recipe; not required.)

**Approach:**
- In a fresh shell, export the synthetic env (verbatim from the ticket):
  - `SYMPHONY_ISSUE_ID=23b5c4c0-d7d8-4114-af57-93e4b0b0e402` (PRO-23 UUID)
  - `SYMPHONY_ISSUE_IDENTIFIER=PRO-23`
  - `SYMPHONY_PROJECT_ID=bb1fe7b3-946c-488a-b4f8-a11e0d346c77`
  - `SYMPHONY_WORKSPACE=$(mktemp -d)`
  - `SYMPHONY_BRANCH=test-branch`
  - `SYMPHONY_ATTEMPT=1`
- Confirm the existing Plane env (`PLANE_API_KEY`, `PLANE_WORKSPACE_SLUG=ccm-design`, `PLANE_BASE_URL=https://api.plane.so`) is present in the shell — these are already in `~/.zshrc` per the env block in the kickoff.
- Run `bash ~/.claude/symphony-hooks/hooks/after_create.sh`. Confirm exit zero.
- Assert: `test -s "$SYMPHONY_WORKSPACE/.symphony/ticket-thread.md"` (file exists and non-empty) — exits zero.
- Assert: `test -s "$SYMPHONY_WORKSPACE/.symphony/issue-body.md"` (file exists and non-empty) — exits zero.
- Read `.symphony/ticket-thread.md` and confirm at least one line of the form `[<iso8601>] <actor>: <body>`. Count lines: should match the live comment count on PRO-23 (or 50, whichever is smaller).
- Run `bash ~/.claude/symphony-hooks/hooks/before_run.sh`. Confirm exit zero. Confirm both files are still non-empty (and `ticket-thread.md` may have grown if a comment landed mid-test).
- Optional: also run `bash ~/.claude/symphony-hooks/hooks/after_run.sh` (with `SYMPHONY_ATTEMPT_RESULT=succeeded`) and confirm `$SYMPHONY_WORKSPACE/.symphony/attempts.log` has one new tab-separated line.

**Patterns to follow:**
- Treat each hook as an integration test against the live Plane API. No mocking — the whole point is to verify the bash scripts plus the API plus the env chain end-to-end.

**Test scenarios:**
- Happy path: All env vars set, `PLANE_API_KEY` valid, PRO-23 has comments → `.symphony/ticket-thread.md` and `.symphony/issue-body.md` are non-empty after `after_create.sh`. Both `test -s` assertions pass.
- Happy path: `before_run.sh` rewrites both files (idempotent re-fetch). Files remain non-empty.
- Happy path: `ticket-thread.md` line count == comment count on PRO-23 (or 50, whichever is smaller). Each line matches the regex `^\[.+\] .+: .*$`.
- Edge case: `PLANE_API_KEY` unset or invalid → `lib/plane.sh` exits non-zero with `PLANE_API_KEY not set` (built-in `:?` check). Hook fails fast. Documented but not part of the green-path acceptance.
- Edge case: PRO-23 has zero comments → `ticket-thread.md` is empty (zero-byte file). R6 says "non-empty" — handled by the precondition that PRO-23 already has comments. Verified during test execution; if zero, the implementer adds one comment to PRO-23 before re-running (e.g., a `🧪 Testing PRO-24 hooks` line) and notes this in the PR body.
- Error path: `mktemp -d` fails (extremely rare; disk full) → hook fails before any Plane call. Out of scope to handle gracefully.

**Verification:**
- All assertions above pass.
- The implementer captures the recipe exit codes and file sizes in the PR body so a reviewer can re-run and compare.

---

- U5. **Boot Symphony against `WORKFLOW.md` and verify candidate fetch + hook firing**

**Goal:** Confirm that Symphony parses the WORKFLOW.md, returns exactly the 3 Symphony-module cards as candidates, fires `after_create` against at least one of them, and produces a populated `.symphony/ticket-thread.md` in the agent's workspace.

**Requirements:** R8, R9

**Dependencies:** U3 (WORKFLOW.md authored), U4 (synthetic test green — proves the hooks work in isolation, isolating any boot issues to Symphony parsing rather than hook bugs).

**Files:**
- (No repo files created. Symphony allocates ephemeral workspaces under its own runtime directory.)

**Approach:**
- From the fork root: `cd elixir && mix symphony.run --workflow ../WORKFLOW.md` (path is relative to `elixir/`; absolute path also works).
- Watch the log output. Expect:
  - Symphony parses tracker config: `kind: plane`, project `PRO`, module `Symphony`.
  - Plane adapter (from PRO-23) runs the candidate fetch and reports 3 cards: PRO-23, PRO-24, PRO-25.
  - Symphony picks the first eligible card (likely PRO-25 or PRO-23 depending on ordering — they're all `Todo`/`In Progress`-eligible per `active_states`).
  - `after_create` hook fires; log line shows the script ran.
  - The `codex.command: echo` is invoked; produces no-op output.
  - Symphony records the attempt and either retries or moves on.
- Open the agent's allocated workspace (logged by Symphony, typically under `/tmp/symphony-*` or a configured `workspaces_dir`). Inspect `.symphony/ticket-thread.md`. Confirm it's populated.
- After ~30–60 seconds of observation, gracefully stop Symphony with `Ctrl+C`. Confirm clean shutdown (no orphaned worktrees in the configured workspace dir; if any, document in PR body).

**Patterns to follow:**
- Symphony framework's standard `mix symphony.run` invocation. No custom flags beyond `--workflow`.

**Test scenarios:**
- Happy path: Symphony boots, candidate fetch returns 3 cards (all Symphony-module: PRO-23, PRO-24, PRO-25). No stray cards from outside the module. Confirms the PRO-23 adapter wiring is intact.
- Happy path: `after_create` fires. Workspace gets `.symphony/ticket-thread.md` populated.
- Edge case: Codex `echo` succeeds (exit 0). `after_run` fires with `SYMPHONY_ATTEMPT_RESULT` set to whatever Symphony assigns for a no-op codex run.
- Edge case: A card transitions to a terminal state during the test (unlikely with `echo`, but possible if a human moves it). `before_remove` fires and posts a "Workspace cleaned up" comment. Documented as expected if observed.
- Error path: Symphony fails to parse WORKFLOW.md → boot fails fast with a YAML or schema error. Implementer fixes the YAML and re-runs.
- Error path: Hook absolute path is wrong → Symphony logs a hook failure. Implementer corrects the path in WORKFLOW.md and re-runs.

**Verification:**
- Symphony log shows exactly 3 candidate cards, all with the `PRO-` identifier prefix, all in the Symphony module.
- Workspace allocation log line points at a directory that contains a populated `.symphony/ticket-thread.md` post-`after_create`.
- No errors in stderr beyond the `echo` no-op output.
- `git status` in the fork shows the worktree clean (no committed-but-untracked changes from Symphony's worktree allocation, since Symphony isolates its workspaces).

---

- U6. **Author small `symphony-hooks/README.md` for the install recipe**

**Goal:** Give a future operator (or reviewer) a self-contained command to install the hooks at the host path, including the chmod and a one-liner per hook describing its job.

**Requirements:** R4 (source-of-truth in fork), R10 (PR documents responsibilities)

**Dependencies:** U1 (the directory must exist).

**Files:**
- Create: `symphony-hooks/README.md`

**Approach:**
- ~30–60 lines, plain markdown, no emojis (per CLAUDE.md guidance — the `before_remove.sh` cleanup-comment emojis come from upstream Symphony convention, not new content).
- Sections: (1) What this is — one paragraph linking back to PRO-24 and the docs/plans entry. (2) Install — the `cp -R + chmod +x` recipe targeting `~/.claude/symphony-hooks/`. (3) Per-hook responsibilities — four bullets mirroring the comment headers in each `.sh` file. (4) Synthetic test recipe — copy-paste of the env block from U4 + the two `test -s` assertions. (5) Pointer to upstream source kit at `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/` for full integration context.
- No env vars or secrets in the file. The README assumes the operator has `PLANE_API_KEY` etc. set in their shell.

**Patterns to follow:**
- Existing fork README at `README.md` (the upstream openai/symphony one) for general tone; this one is a sibling file scoped to the hooks directory.

**Test scenarios:**
- Test expectation: none — documentation file, no executable behavior.

**Verification:**
- File exists, ~30–60 lines, sections present.
- The install recipe in the README, copy-pasted verbatim into a fresh shell, reproduces the host-install state from U2.

---

- U7. **Open PR titled `feat(symphony): add Plane lifecycle hooks + workflow`**

**Goal:** Land all the above on the fork's `dev` branch via a PR (per user CLAUDE.md: worktree → PR → merge to dev).

**Requirements:** R10

**Dependencies:** U1, U3, U4, U5, U6 all green (host-side U2 is reproducible from the committed `symphony-hooks/` tree, so it's not a commit prerequisite).

**Files:**
- (PR-only — no new repo files. Existing files from U1, U3, U6 are committed.)

**Approach:**
- Confirm the worktree is on `feature/PRO-24-lifecycle-hooks` (it is, per kickoff).
- Verify `git status` is clean apart from the new files: `symphony-hooks/{hooks,lib,README.md}/...`, `WORKFLOW.md`, `docs/plans/2026-05-02-002-feat-symphony-lifecycle-hooks-plan.md`.
- Stage and commit. Suggested commit message: `feat(symphony): add Plane lifecycle hooks + workflow` with body summarizing the four hooks and the synthetic test command. (Plan does not author the actual commit message — that's `ce-work` / `ce-commit` territory.)
- Push the branch and open a PR against `dev`. PR title: `feat(symphony): add Plane lifecycle hooks + workflow`. PR body must include:
  - One paragraph framing the change ("hooks + WORKFLOW.md, no codex pipeline yet — that's PRO-25").
  - Per-hook responsibility table (4 rows).
  - The verbatim synthetic test recipe from U4 (env block + two assertions).
  - The `mix symphony.run` boot recipe from U5 with expected log signals.
  - Manual install command (`cp -R symphony-hooks ~/.claude/symphony-hooks && chmod +x ~/.claude/symphony-hooks/hooks/*.sh`).
  - Explicit "out of scope" callout pointing at PRO-25 for the codex command swap.
- Do not merge. Per user CLAUDE.md, never merge to `main` without explicit permission. PRs targeting `dev` are merged by the user or by an explicit instruction in a later turn.

**Patterns to follow:**
- The PR style of the PRO-23 PR (already merged). Same structure: framing paragraph, change summary, test recipe, scope/non-scope callout.

**Test scenarios:**
- Test expectation: none — workflow / process step.

**Verification:**
- `gh pr view` (or equivalent) shows the PR exists, targets `dev`, and has the expected title.
- All seven of the above items are present in the PR body.
- CI (if configured on the fork) is green or pending; no immediate failures.

---

## System-Wide Impact

- **Interaction graph:** The hooks are invoked by the Symphony framework's lifecycle dispatch, not by other Elixir code in the fork. They sit outside the BEAM VM entirely (bash subprocess). The only cross-cutting touchpoint is the env contract (`SYMPHONY_*` vars Symphony sets, `PLANE_*` vars the user's shell sets) and the file contract (`.symphony/ticket-thread.md`, `.symphony/issue-body.md`, `.symphony/attempts.log` written under `$SYMPHONY_WORKSPACE`).
- **Error propagation:** `after_create.sh` is load-bearing — failure aborts the run (`set -euo pipefail`). `before_run.sh` failure aborts the current attempt; Symphony will retry per its own policy. `after_run.sh` and `before_remove.sh` failures are tolerated (`|| true` in the `before_remove` cleanup comment, and the script logs telemetry but does not gate progress).
- **State lifecycle risks:** None in this card — codex is `echo`, so no card transitions occur during verification. The cleanup comment from `before_remove.sh` is the only Plane-side write the hooks issue, and it only fires on terminal-state transition. PRO-25 will exercise the full state lifecycle.
- **API surface parity:** The `lib/plane.sh` helpers parallel `SymphonyElixir.Plane.Client` Elixir module endpoints. If the Elixir client adds a new endpoint shape (e.g., for `blocked_by` resolution from PRO-23's deferred work), `lib/plane.sh` may want a parallel helper, but that's a future concern, not part of this card.
- **Integration coverage:** The synthetic test (U4) exercises live Plane API calls. The Symphony boot test (U5) exercises Symphony's hook dispatch + the Plane adapter (from PRO-23) + the bash hooks all together. Together these are the only behavioral verification this card produces — there are no Elixir unit tests added.
- **Unchanged invariants:** `elixir/lib/symphony_elixir/**` is not touched. The PRO-23 adapter, client, and issue modules remain exactly as merged. `tracker.ex` dispatch, `mix.exs` deps — all unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `WORKFLOW.md` absolute paths embed `/Users/claudiomendonca/...`, breaking portability for any future co-developer. | Documented in Key Technical Decisions. PR body calls it out. PRO-25 (or a follow-up) can templatize via `${HOME}` env substitution if multi-machine setups become a real need. Single-developer scope at this stage makes this acceptable. |
| Symphony's hook env contract may have undocumented vars or shapes that differ from what `lib/plane.sh` expects. | The synthetic test (U4) doesn't go through Symphony — it directly sets the env vars per the ticket spec. So if Symphony sets a different shape, U5 catches it during boot. The fix is then localized to either WORKFLOW.md or a hook variable read. |
| `plane_dump_comments` produces shape Symphony's prompt-include directive can't parse (e.g., embedded literal `{%` Liquid tokens in a comment body). | Ticket comments on PRO-23 are agent-authored, no Liquid syntax. If a future card has user-typed `{%` content, the prompt rendering would error. Out of scope for this card; logged as a sharp edge for PRO-25 to handle (e.g., escape via the hook). |
| `chmod +x` doesn't propagate through `git` for a checkout on a fresh machine. | Git does preserve the executable bit by default. If a clone reports the bit missing, the install README's `chmod +x` step is the recovery — same command that was applied at install time. |
| `.symphony/issue-body.md` for PRO-23 contains HTML (Plane stores `description_html` and `description_stripped`). The hook prefers `description_stripped`; if absent, falls back to `description_html`. | Already handled by the drafted hook (`jq -r '.description_stripped // .description_html // ""'`). No mitigation needed. |
| The `Symphony` module on the `PRO` Plane project may not exist or may not contain exactly 3 cards by the time U5 runs. | The user's env block confirms `PLANE_MODULE_NAME=Symphony` is the expected value. PRO-23 used this same module in its verification. If the module is empty or has a different card count, U5's R8 assertion fails — implementer either reconciles by listing module contents (`gws` is irrelevant here; use `curl` against `/modules/<id>/module-issues/`) or adjusts the assertion. |
| `before_remove.sh` posts a cleanup comment to a Plane card during the boot test (unintended side effect on production data). | Codex is `echo`, so no state transitions, so `before_remove` should not fire. If it does (rare race or human-driven move), the comment is a single benign HTML paragraph and is recoverable (operator deletes via Plane UI). Acceptable risk given the value of full lifecycle verification. |

---

## Alternative Approaches Considered

- **Approach A: `extras/symphony-hooks/` in the fork.** Buries the hooks under `extras/`, which connotes "optional, tangential, possibly unsupported." For a load-bearing integration that PRO-25 directly depends on, top-level placement signals importance better. Rejected for discoverability.
- **Approach B: Keep the hooks ONLY at the source path (`~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/hooks/`) and have the fork contain just `WORKFLOW.md`.** This works but couples the fork to a specific user's local Obsidian-extras path forever. Anyone who clones the fork has no path to the actual hook scripts without going to the obsidian-extras repo, which isn't part of openai/symphony's lineage. Rejected because it makes the fork non-self-contained.
- **Approach C (chosen): `symphony-hooks/` at the fork root, plus host install at `~/.claude/symphony-hooks/`.** Mirrors the host install layout exactly. Fork is the source of truth. Operator runs `cp -R symphony-hooks ~/.claude/symphony-hooks && chmod +x ...` to install. WORKFLOW.md references the host path so it's portable across repos managed by Symphony. Picked.
- **Approach D: Symlink instead of copy at install time.** Tempting because it keeps the host install in sync with the fork. Rejected because (a) Symphony may run the hook from any working directory, and a symlink to a worktree path becomes stale if the worktree is removed; (b) a fresh clone of the fork on a different machine would still need the cp recipe — symlinking only saves work on the developer's primary machine; (c) the source-of-truth question gets fuzzy when both are "active."

---

## Documentation / Operational Notes

- The PR body itself is the primary documentation deliverable for this card. It mirrors the structure called out in U7.
- `symphony-hooks/README.md` (U6) provides operator-facing install + per-hook responsibilities for anyone discovering the directory in the fork.
- No `docs/solutions/` entry is created in this card. If the synthetic-test or boot-test recipe surfaces a non-obvious gotcha (e.g., Symphony env quirk, `mix symphony.run` flag drift), the implementer adds a `docs/solutions/2026-05-02-symphony-hook-boot-quirks.md` entry as a "noticed but not touched"-style postscript — but this is not part of acceptance.
- Operational note: future operators on different machines will need to either (a) edit `WORKFLOW.md` to substitute their `$HOME`, or (b) wait for PRO-25 (or a follow-up) to introduce an env-substitution pass. Single-developer scope makes this acceptable for now.
- The `~/.symphony/snapshots/<identifier>/attempts.log` directory grows monotonically with each card the operator runs through Symphony. No retention policy in this card; operator manually prunes if it becomes large.

---

## Sources & References

- Ticket: PRO-24 in the `PRO` Plane project (workspace `ccm-design`, module `Symphony`).
- Pre-drafted source kit: `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/{hooks,lib,workflow,README.md}`.
- Sibling plan: `docs/plans/2026-05-02-001-feat-plane-tracker-adapter-plan.md` (PRO-23, merged).
- Follow-on ticket: PRO-25 (full `/lfg-symphony` pipeline).
- Plane API quirks reference: `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/README.md` lines 133–185 (verified May 2026 against cloud Plane).
- User CLAUDE.md global rule: "worktree → PR → merge to dev. Never merge to main without explicit permission." Applies to this card's PR target choice.
- Symphony framework (upstream openai/symphony): hook schema, env contract, `mix symphony.run` invocation pattern.
