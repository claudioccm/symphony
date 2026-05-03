---
title: "feat: Add Plane tracker adapter for Symphony"
type: feat
status: active
date: 2026-05-02
---

# feat: Add Plane tracker adapter for Symphony

## Summary

Implement the `SymphonyElixir.Tracker` behaviour against the Plane REST API so Symphony can poll a Plane project (scoped to a Plane "Module"), normalize work items into Symphony's existing `Issue` struct, post comments, and move states. Three pre-drafted source files (`plane_adapter.ex`, `plane_client.ex`, `plane_issue.ex`) plus a one-line dispatch patch and a verification shell script already exist in `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/`; this plan copies/adapts them into `elixir/lib/symphony_elixir/plane/`, wires dispatch in `tracker.ex`, adds unit tests against mocked `Req`, and verifies against a live Plane workspace via the pre-flight script.

---

## Problem Frame

Symphony currently dispatches its `Tracker` behaviour to a `Memory` adapter (tests) or to `SymphonyElixir.Linear.Adapter` (default). For users who run their tickets in [Plane](https://plane.so) instead of Linear, Symphony has no way to fetch candidate issues, post comments, or move states — making the rest of the Compound Engineering pipeline (LFG, Symphony orchestrator, `lfg-symphony` per-card workflow) unusable on Plane-backed projects. PRO-23 itself is a Plane card and is the first card the resulting adapter must successfully read.

---

## Requirements

- R1. Implement all five `SymphonyElixir.Tracker` callbacks against Plane: `fetch_candidate_issues/0`, `fetch_issues_by_states/1`, `fetch_issue_states_by_ids/1`, `create_comment/2`, `update_issue_state/2`.
- R2. Scope reads to a single Plane Module when `PLANE_MODULE_ID` or `PLANE_MODULE_NAME` is configured; route through `/modules/<MID>/module-issues/` rather than the bare work-items endpoint (module filter params are ignored on `/work-items/` — see Key Technical Decisions).
- R3. Normalize Plane work-items into a `SymphonyElixir.Plane.Issue` struct shape-compatible with `SymphonyElixir.Linear.Issue` (same fields the orchestrator consumes: `id`, `identifier`, `title`, `description`, `priority`, `state`, `branch_name`, `url`, `assignee_id`, `labels`, `assigned_to_worker`, `blocked_by`, `created_at`, `updated_at`).
- R4. Map Plane priority enum (`urgent`, `high`, `medium`, `low`, `none`) to Symphony's integer priority. Synthesize `branch_name` from identifier + title slug when no custom property carries one.
- R5. Wire `"plane"` into `SymphonyElixir.Tracker.adapter/0` so workflows declaring `tracker.kind: "plane"` route to `SymphonyElixir.Plane.Adapter`. Linear remains the catch-all default.
- R6. `verify-plane-env.sh` must continue to exit 0 with all 7 sections green when run with `PLANE_PROJECT_IDENTIFIER=PRO PLANE_MODULE_NAME=Symphony`.
- R7. `SymphonyElixir.Plane.Adapter.fetch_candidate_issues/0` from `iex -S mix` returns exactly the 3 cards in the Symphony module (PRO-23, PRO-24, PRO-25). Zero stray cards from outside the module.
- R8. `mix test` passes; new tests cover module-scoping path, state filter, comment post, state update, and `Issue.from_payload` priority-enum + branch-name synthesis.
- R9. PR opened on the fork against its `main` branch with title `feat(plane): add Plane tracker adapter` and a description summarizing the three Plane API quirks.

---

## Scope Boundaries

- Symphony lifecycle hooks (`hooks/*.sh` in the source kit) — owned by PRO-24.
- The `lfg-symphony` headless command — owned by PRO-25.
- Webhook-driven invalidation of polling — explicit non-goal, deferred per ticket.
- Pagination beyond the first 100 issues — explicit non-goal; first page is sufficient for the PRO module.
- `blocked_by` resolution via Plane's `/relations/` endpoint — `Plane.Issue.from_payload/2` returns `[]` for now (the relations quirk is documented for the follow-up).
- Retry / backoff on HTTP 429 — surface the error and skip the cycle; no retry layer.
- Custom-property support for `branch_name` — synthesized from `identifier + slug(title)` only.

### Deferred to Follow-Up Work

- Symphony lifecycle hook wiring (`after_create.sh`, `before_run.sh`, `after_run.sh`, `before_remove.sh`): PRO-24.
- `/lfg-symphony` Claude Code slash command: PRO-25.
- Plane webhook receiver for sub-poll-interval Needs Decision resume: future phase 2 (see `extras/symphony-plane-ce/docs/PHASE2-WEBHOOKS.md`).
- Pagination, `blocked_by` resolution, 429 retry: future iteration on the same adapter.

---

## Context & Research

### Relevant Code and Patterns

- `elixir/lib/symphony_elixir/tracker.ex` — defines the `@behaviour` and the `adapter/0` dispatch we extend.
- `elixir/lib/symphony_elixir/linear/adapter.ex` — reference implementation of the Tracker behaviour against a remote tracker. Mirror its public-function structure (each callback delegates to a private client call + a normalization step).
- `elixir/lib/symphony_elixir/linear/issue.ex` — reference for `defstruct` shape; `Plane.Issue` mirrors these fields.
- `elixir/lib/symphony_elixir/linear/client.ex` — pattern for a thin HTTP client module separated from adapter logic. `plane_client.ex` follows the same split.
- `elixir/lib/symphony_elixir/tracker/memory.ex` — used in `tracker.kind: "memory"` test mode; relevant only insofar as tests must not regress the Memory adapter path.
- `elixir/mix.exs` line 72 — `{:req, "~> 0.5"}` already declared, no dep change needed.

### Pre-drafted source kit (to be copied/adapted)

- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/adapters/plane_adapter.ex` — 233 lines; implements the five callbacks. Copy into `elixir/lib/symphony_elixir/plane/adapter.ex`.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/adapters/plane_client.ex` — 260 lines; thin Req wrapper. Copy into `elixir/lib/symphony_elixir/plane/client.ex`.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/adapters/plane_issue.ex` — 131 lines; normalized struct. Copy into `elixir/lib/symphony_elixir/plane/issue.ex`.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/patches/0001-add-plane-tracker-dispatch.patch` — single-line addition to `tracker.ex`. Apply with `git apply`; if anchor drift, hand-edit per the diff.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/verify-plane-env.sh` — 7-section pre-flight verifier. Read-only, side-effect-free. Used as final acceptance check.
- `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/README.md` — full integration context including the three Plane API quirks (lines 133–185 in particular).

### Institutional Learnings

- None applicable from `docs/solutions/` for this adapter (greenfield integration).

### External References

- Plane REST API: `https://api.plane.so/api/v1/workspaces/<slug>/projects/<id>/...`. Authoritative quirks documented at `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/README.md` lines 133–185, verified against cloud Plane May 2026.
- The user-level `plane-api` skill is also available for ad-hoc Plane REST calls if questions arise during implementation.

---

## Key Technical Decisions

- **Module scoping uses `/modules/<MID>/module-issues/` (NOT `/work-items/?module_ids=`)**: Plane's bare `/work-items/` endpoint silently ignores `module_ids`, `module`, and `modules` query params and returns project-wide results. Only `module-issues/` actually filters. The adapter's `list_module_work_items/3` is the single source of truth for module-scoped reads. Don't "fix" this to look like the obvious endpoint — it's wrong.
- **Two-step work-item creation pattern documented even though we don't create work items in this adapter**: `module_ids` in the POST body is silently dropped. To put a work item in a module, you POST the work item, then POST `{"issues": [<uuid>]}` to `/modules/<MID>/module-issues/`. The adapter scope is read + comment + state-move only, but the client module documents this pattern for the follow-up tickets that will create cards.
- **Issue relations endpoint is `/relations/` (NOT `/issue-relations/`)**: `/issue-relations/` returns 404. The body shape is `{"issues": [<uuid>,...], "relation_type": "blocked_by"}` — multi-issue array keyed `issues`, not singular `related_issue`. `Issue.from_payload/2` returns `[]` for `blocked_by` in this iteration; the endpoint shape is preserved in client comments for the follow-up.
- **State resolution by name**: each callback that takes a state name (`fetch_issues_by_states`, `update_issue_state`) resolves name → UUID against the project's state list. Cache states once per process / per call cycle to avoid N+1 lookups when filtering by multiple states.
- **Priority mapping**: Plane's enum (`urgent` | `high` | `medium` | `low` | `none`) maps to Symphony's integer priority (Linear convention: 1=urgent, 2=high, 3=medium, 4=low, 0=none). `Plane.Issue.from_payload/2` is the single conversion point.
- **`branch_name` synthesis**: `identifier + "/" + slug(title)` when no custom property carries one. Same shape Linear adapter produces.
- **Dispatch order in `tracker.ex`**: `"memory"` first (test mode), `"plane"` second (new), Linear as catch-all `_`. Preserves Linear-as-default behavior for any value other than the two named adapters.
- **Config surface**: read from env vars (`PLANE_API_KEY`, `PLANE_WORKSPACE_SLUG`, `PLANE_BASE_URL`, `PLANE_PROJECT_IDENTIFIER`, optionally `PLANE_MODULE_ID` or `PLANE_MODULE_NAME`). The client resolves identifier → project UUID and module name → module UUID at startup. No additions to `Config.settings!()` schema in this iteration.

---

## Open Questions

### Resolved During Planning

- Is `{:req, "~> 0.5"}` already in `mix.exs`? — Yes, line 72. No dep change required, no `mix deps.get` needed beyond the implementer's normal post-pull refresh.
- Does the patch apply cleanly against current `tracker.ex`? — Patch targets line 38–43 of `tracker.ex`; the current file has the `case` block at exactly that location, so `git apply` should succeed. If upstream has shifted, the README's hand-edit fallback is a one-line insert.
- Where do tests live? — `elixir/test/symphony_elixir/plane/` (mirroring `elixir/lib/symphony_elixir/plane/`); the `elixir/test/symphony_elixir/` directory currently has flat-style files but the Linear adapter's tests don't exist there at all (Linear is tested through orchestrator/integration tests). For Plane we add a dedicated subdir to keep adapter tests close to the adapter. Confirmed by ticket step 7.

### Deferred to Implementation

- Exact unused-alias warnings produced by `mix compile` after the copy step — depends on what the source files import vs. what the integrated paths need. Implementer fixes by removing or renaming as Elixir flags them.
- Whether `verify-plane-env.sh` Section 7 (candidate-fetch parity) drifts due to module identity churn between plan-time and execution-time — if it drifts, re-run the verifier and update `PLANE_MODULE_NAME` accordingly. The script is the source of truth.

---

## Output Structure

```
elixir/
  lib/symphony_elixir/
    plane/
      adapter.ex          (new — copied from extras/symphony-plane-ce/adapters/plane_adapter.ex)
      client.ex           (new — copied from extras/symphony-plane-ce/adapters/plane_client.ex)
      issue.ex            (new — copied from extras/symphony-plane-ce/adapters/plane_issue.ex)
    tracker.ex            (modify — one-line patch adds "plane" dispatch clause)
  test/symphony_elixir/
    plane/
      adapter_test.exs    (new)
      client_test.exs     (new)
      issue_test.exs      (new)
docs/
  plans/
    2026-05-02-001-feat-plane-tracker-adapter-plan.md   (this file)
```

---

## Implementation Units

- U1. **Copy adapter source files into elixir/lib/symphony_elixir/plane/**

**Goal:** Land the three pre-drafted Elixir source files in their integrated path with module names matching the directory structure.

**Requirements:** R1, R3, R4

**Dependencies:** None

**Files:**
- Create: `elixir/lib/symphony_elixir/plane/adapter.ex`
- Create: `elixir/lib/symphony_elixir/plane/client.ex`
- Create: `elixir/lib/symphony_elixir/plane/issue.ex`

**Approach:**
- `mkdir -p elixir/lib/symphony_elixir/plane/`.
- Copy `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/adapters/plane_adapter.ex` → `elixir/lib/symphony_elixir/plane/adapter.ex`. The source file declares `defmodule SymphonyElixir.Plane.Adapter`; verify it matches the integrated path. Same for `plane_client.ex` → `client.ex` (`SymphonyElixir.Plane.Client`) and `plane_issue.ex` → `issue.ex` (`SymphonyElixir.Plane.Issue`).
- Do not edit the copied content in this unit. Subsequent units adjust as needed.

**Patterns to follow:**
- Directory layout mirrors `elixir/lib/symphony_elixir/linear/{adapter,client,issue}.ex`.

**Test scenarios:**
- Test expectation: none -- pure file copy with no behavioral change. Behavioral coverage lands in U4–U6.

**Verification:**
- The three files exist at the integrated paths.
- Each file's `defmodule` declaration matches its path.

---

- U2. **Apply the tracker dispatch patch**

**Goal:** Wire `"plane"` into `SymphonyElixir.Tracker.adapter/0` so workflows with `tracker.kind: "plane"` route to the new adapter.

**Requirements:** R5

**Dependencies:** U1 (the target module must exist before dispatch references it).

**Files:**
- Modify: `elixir/lib/symphony_elixir/tracker.ex`

**Approach:**
- From the worktree root: `git apply ~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/patches/0001-add-plane-tracker-dispatch.patch`.
- If `git apply` rejects (anchor drift), hand-edit `tracker.ex` per the README fallback: insert `"plane" -> SymphonyElixir.Plane.Adapter` between the `"memory"` clause and the catch-all `_` clause inside `def adapter`.
- Preserve the existing dispatch order: `"memory"` → `"plane"` → catch-all Linear.

**Patterns to follow:**
- Existing case-statement style in `Tracker.adapter/0`.

**Test scenarios:**
- Happy path: `Config.settings!().tracker.kind == "plane"` → `Tracker.adapter/0` returns `SymphonyElixir.Plane.Adapter`.
- Edge case: `Config.settings!().tracker.kind == "memory"` still returns `SymphonyElixir.Tracker.Memory` (no regression).
- Edge case: `Config.settings!().tracker.kind == "linear"` (or any unknown value) falls through to `SymphonyElixir.Linear.Adapter`.

**Verification:**
- Existing Tracker dispatch tests (if any in `core_test.exs` or similar) still pass.
- A quick `iex -S mix` smoke: setting tracker kind to `"plane"` returns the Plane module.

---

- U3. **Compile clean and resolve unused-alias warnings**

**Goal:** `mix compile` produces zero warnings introduced by the new modules.

**Requirements:** R1

**Dependencies:** U1, U2

**Files:**
- Modify (as needed): `elixir/lib/symphony_elixir/plane/adapter.ex`, `elixir/lib/symphony_elixir/plane/client.ex`, `elixir/lib/symphony_elixir/plane/issue.ex`

**Approach:**
- Run `cd elixir && mix compile`.
- Read each warning. Typical class: unused aliases for modules referenced in the source kit but not exercised in this scope (e.g., relations helpers if `Issue.from_payload/2` returns `[]` for `blocked_by`).
- Remove unused aliases or move them behind a `@moduledoc false` helper that's actually called. Do not silence warnings with `_` prefixes unless the binding is intentionally unused for an interface contract.
- Re-run `mix compile` until clean.

**Patterns to follow:**
- Project's existing zero-warning compile baseline.

**Test scenarios:**
- Test expectation: none -- this unit is warning cleanup only. Behavioral verification is in U4–U6.

**Verification:**
- `mix compile` exits 0 and produces no warnings attributable to `lib/symphony_elixir/plane/*`.

---

- U4. **Unit tests for `SymphonyElixir.Plane.Issue` normalization**

**Goal:** Cover priority-enum mapping, `branch_name` synthesis, and the basic `from_payload/2` shape so the orchestrator can rely on Plane issues looking like Linear issues.

**Requirements:** R3, R4, R8

**Dependencies:** U1

**Files:**
- Create: `elixir/test/symphony_elixir/plane/issue_test.exs`

**Approach:**
- Pure data-shape tests; no HTTP. Construct representative Plane work-item payload maps inline (or via a small fixture helper) and assert `Plane.Issue.from_payload/2` produces the expected struct.
- Cover each priority enum value individually so the mapping table can't silently drift.
- Cover `branch_name` synthesis from `identifier + title` (slugged) when no custom property carries one.

**Patterns to follow:**
- Existing test style under `elixir/test/symphony_elixir/`.

**Test scenarios:**
- Happy path: Payload with `priority: "high"` → struct with `priority: 2`.
- Happy path: Payload with `priority: "urgent"` → `priority: 1`.
- Happy path: Payload with `priority: "medium"` → `priority: 3`.
- Happy path: Payload with `priority: "low"` → `priority: 4`.
- Edge case: Payload with `priority: "none"` → `priority: 0`.
- Edge case: Payload with `priority: nil` → `priority: 0` (or whatever the source kit defines as the default; assert what the implementation does).
- Happy path: Payload with `name: "Plane tracker adapter for Symphony"` and `identifier: "PRO-23"` → `branch_name` containing `pro-23` and `plane-tracker-adapter-for-symphony` (or the source kit's exact slug shape).
- Edge case: Title with punctuation, accented characters, or trailing whitespace → slug is lowercased, hyphenated, and stripped of non-alphanumerics.
- Happy path: All fields the orchestrator consumes (`id`, `identifier`, `title`, `description`, `state`, `url`, `assignee_id`, `labels`, `created_at`, `updated_at`) are present and typed as documented in `Plane.Issue`'s `@type t :: ...`.
- Edge case: `blocked_by` is always `[]` in this iteration regardless of payload contents.

**Verification:**
- `mix test test/symphony_elixir/plane/issue_test.exs` is green.

---

- U5. **Unit tests for `SymphonyElixir.Plane.Client` against mocked `Req`**

**Goal:** Lock the request shape (URL, headers, body) the client emits for each operation, especially the module-scoping path that's the most prone to regression-by-fix.

**Requirements:** R1, R2, R6, R8

**Dependencies:** U1

**Files:**
- Create: `elixir/test/symphony_elixir/plane/client_test.exs`

**Approach:**
- Use `Req.Test` (built-in stub support in Req ~> 0.5) or `Mox` against a stub adapter to intercept HTTP. Assert the URL path, query params, headers (`X-API-Key`), and JSON body for each operation.
- For module-scoping coverage: assert that when a module is configured, the client hits `/api/v1/workspaces/<slug>/projects/<pid>/modules/<mid>/module-issues/` and NOT `/api/v1/workspaces/<slug>/projects/<pid>/work-items/`. This is the load-bearing test that prevents a future "fix" from re-introducing the broken filter path.
- For comment post: assert path `/work-items/<wid>/comments/` and a markdown→HTML transform on the body if the source kit applies one.
- For state update: assert path `/work-items/<wid>/` PATCH with `{"state": "<state-uuid>"}`.

**Patterns to follow:**
- `elixir/test/symphony_elixir/` test conventions; ExUnit `setup` blocks with stubbed Req owners.

**Test scenarios:**
- Happy path: `list_module_work_items/3` builds URL `/modules/<MID>/module-issues/?state=<UUID>` (one or more `state` params).
- Happy path: `list_project_work_items/2` (no module configured) builds URL `/work-items/?state=<UUID>` against the project endpoint.
- Edge case: Multiple state UUIDs append as repeated `?state=<a>&state=<b>` query params.
- Edge case: Empty state list still produces a valid URL (no trailing `?` or stray `&`).
- Error path: HTTP 401 from auth failure surfaces as `{:error, :unauthorized}` (or whatever shape the source kit defines) without retry.
- Error path: HTTP 429 surfaces as `{:error, :rate_limited}` and is NOT retried (per scope).
- Error path: Network timeout surfaces as `{:error, _reason}` cleanly.
- Happy path: `create_comment/3` POSTs to `/work-items/<wid>/comments/` with body `{"comment_html": "<p>...</p>"}` (or `comment_html` / `description_html` whichever the source kit settled on). Covers the markdown→HTML transform if present.
- Happy path: `update_issue_state/3` PATCHes `/work-items/<wid>/` with `{"state": "<state-uuid>"}` after resolving the state name to a UUID.
- Integration scenario: Auth header `X-API-Key: <PLANE_API_KEY>` is present on every request.
- Edge case: Self-hosted base URL (override of `PLANE_BASE_URL`) is honored.
- Covers AE: module-scoping URL path matches the README quirk note (`module-issues/` not `work-items/?module_ids=`).

**Verification:**
- `mix test test/symphony_elixir/plane/client_test.exs` is green.

---

- U6. **Unit tests for `SymphonyElixir.Plane.Adapter` callback wiring**

**Goal:** Cover each Tracker callback end-to-end against a mocked client, focusing on the orchestration-relevant invariants (state name → UUID resolution, candidate-fetch composition, comment + state-move dispatch).

**Requirements:** R1, R2, R7, R8

**Dependencies:** U1, U4 (Issue normalization), U5 (Client request shape)

**Files:**
- Create: `elixir/test/symphony_elixir/plane/adapter_test.exs`

**Approach:**
- Mock `SymphonyElixir.Plane.Client` (Mox or behaviour-based stub) so adapter logic is tested independent of HTTP.
- Cover the three module-vs-no-module branches in candidate fetch.
- Cover state-name → UUID resolution as a separate concern from list-fetch.

**Patterns to follow:**
- Linear adapter would be the natural reference if it had unit tests; absent that, mirror the test conventions in `elixir/test/symphony_elixir/core_test.exs`.

**Test scenarios:**
- Happy path: `fetch_candidate_issues/0` with module configured → calls client's module-scoped list and returns normalized `Plane.Issue` structs.
- Happy path: `fetch_candidate_issues/0` with no module configured → falls back to project-scoped list.
- Happy path: `fetch_issues_by_states/1` resolves each state name to UUID once, then issues a single list call with the resolved UUIDs.
- Edge case: `fetch_issues_by_states/1` with an unknown state name returns `{:error, {:unknown_state, name}}` (or whatever shape the source kit defines) without making the list call.
- Happy path: `fetch_issue_states_by_ids/1` returns `{:ok, %{<issue_id> => <state_name>, ...}}` for the given issue list.
- Happy path: `create_comment/2` calls client comment-post with the issue UUID and body.
- Happy path: `update_issue_state/2` resolves the state name to UUID, then PATCHes the issue to that state.
- Error path: `update_issue_state/2` with unknown state name surfaces `{:error, {:unknown_state, name}}`.
- Integration scenario: Module-scoping path is exercised — assert the adapter calls the module-scoped client function, NOT the bare project-scoped one, when a module ID is configured. This is the regression-prevention test for Plane quirk #2.
- Edge case: Empty result list from client returns `{:ok, []}`, not `{:error, :empty}`.

**Verification:**
- `mix test test/symphony_elixir/plane/adapter_test.exs` is green.
- `mix test` (whole suite) is green — no regression in Linear or Memory adapter paths.

---

- U7. **Pre-flight live verification**

**Goal:** Confirm the adapter works against the real Plane workspace by running the existing 7-section verifier and the candidate-fetch smoke test from `iex`.

**Requirements:** R6, R7

**Dependencies:** U1, U2, U3, U4, U5, U6

**Files:**
- None modified. Read-only verification.

**Approach:**
- Run the verifier from its source directory (it's a standalone shell script that hits Plane's REST API directly):
  ```
  cd ~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce && \
    PLANE_PROJECT_IDENTIFIER=PRO PLANE_MODULE_NAME=Symphony ./verify-plane-env.sh
  ```
  All 7 sections must stay green. If any section fails, the failure mode is environmental (auth, project identity, module name) — fix env, re-run; do not "fix" the script.
- From the Symphony worktree: `cd elixir && iex -S mix`, then:
  ```elixir
  Application.put_env(:symphony_elixir, :tracker, %{kind: "plane"})  # or via Config
  {:ok, issues} = SymphonyElixir.Plane.Adapter.fetch_candidate_issues()
  Enum.map(issues, & &1.identifier)
  ```
  Expected: `["PRO-23", "PRO-24", "PRO-25"]` (order not asserted; set equality is what matters).
- Live-verify `create_comment/2` and `update_issue_state/2` on a disposable Plane card if one is available; otherwise rely on unit-test coverage and skip live writes (acceptance criteria allow either path provided unit tests cover the dispatch).

**Patterns to follow:**
- The verifier itself is the pattern. Don't reimplement its checks in Elixir.

**Test scenarios:**
- Test expectation: none -- this is a verification unit, not a test-authoring unit. The acceptance criterion is the verifier's exit code + the iex smoke output.

**Verification:**
- `verify-plane-env.sh` exits 0; all 7 sections green.
- `iex` candidate-fetch returns exactly `["PRO-23", "PRO-24", "PRO-25"]`.

---

- U8. **Open the PR on the fork against `main`**

**Goal:** Ship the change for review with a description that summarizes the three Plane API quirks future maintainers will trip on.

**Requirements:** R9

**Dependencies:** U1–U7

**Files:**
- None modified. Git operations only.

**Approach:**
- Commit the work in logical chunks (suggested: U1+U2 as one commit "feat(plane): add adapter + dispatch", U3 as cleanup, U4–U6 as one commit "test(plane): adapter + client + issue tests"). Final commit message style follows the project's existing convention.
- Push the branch to the fork's `origin`.
- Open the PR against the fork's `main` branch (per ticket instructions — fork's `main`, not upstream openai/symphony's `main`).
- PR title: `feat(plane): add Plane tracker adapter`.
- PR body must include a "Plane API quirks" section listing the three traps: (1) module filtering doesn't work on `/work-items/`, (2) `module_ids` dropped at create-time, (3) relations endpoint is `/relations/` not `/issue-relations/`. Reference `extras/symphony-plane-ce/README.md` lines 133–185 for the source-of-truth quirk doc.

**Patterns to follow:**
- Project's existing PR description style if any examples exist under `gh pr list` on the fork.

**Test scenarios:**
- Test expectation: none -- this is a delivery unit. Acceptance is the PR existing with the right title, base, and body.

**Verification:**
- PR exists on the fork against `main` with the specified title.
- PR body summarizes the three Plane API quirks.
- CI (if any is configured on the fork) is green.

---

## System-Wide Impact

- **Interaction graph:** `SymphonyElixir.Tracker.adapter/0` is the only call site that gains a new branch. Orchestrator and `agent_runner` continue to call `Tracker.fetch_candidate_issues/0` etc. with no awareness of which adapter is bound. Plane.Issue is shape-compatible with Linear.Issue for the fields the orchestrator consumes.
- **Error propagation:** Plane HTTP errors (401, 429, 5xx, network) surface as `{:error, reason}` from each callback and propagate up the existing Tracker contract. The orchestrator's existing error-handling for Tracker errors handles them without modification.
- **State lifecycle risks:** No persistence added. Adapter is stateless per call (state-UUID resolution may cache within a single call cycle; not across cycles).
- **API surface parity:** The five Tracker callbacks are the parity surface. Each one has matching coverage in U6.
- **Integration coverage:** U7's live verification is the only true integration check. Unit tests in U4–U6 cover request shape and response normalization but not network behavior end-to-end.
- **Unchanged invariants:** `SymphonyElixir.Linear.Adapter` is unchanged; it remains the catch-all default for any `tracker.kind` that isn't `"memory"` or `"plane"`. `SymphonyElixir.Tracker.Memory` is unchanged. The Tracker behaviour itself is unchanged — no new callbacks, no signature changes.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `git apply` of the dispatch patch fails due to upstream `tracker.ex` drift. | README documents the one-line hand-edit fallback. Implementer attempts patch first; falls back if it rejects. |
| Unused-alias warnings from copied source files block clean compile. | U3 is dedicated to cleanup. Source kit author may have aliased relations helpers used in `Issue.from_payload/2` that we don't exercise (`blocked_by` returns `[]`). |
| Plane API quirks are "fixed" by a well-meaning future change. | All three quirks documented in Key Technical Decisions, in `README.md`, and exercised by U5 + U6 tests. The module-scoping URL test is the load-bearing regression guard. |
| Live verification fails because `PRO` module identity drifted between plan-time and execution-time. | `verify-plane-env.sh` is the single source of truth for module identity; if it disagrees with what's in `iex`, fix env vars to match the verifier's expectation. |
| `Req.Test` stub conventions differ from what the source kit was authored against. | U5 implementer adapts test setup to whatever stub strategy fits the project's existing test harness; the request-shape assertions are what matter, not the specific mocking library. |

---

## Documentation / Operational Notes

- The PR body must summarize the three Plane API quirks (per R9). This is the user-facing record of the institutional learning.
- `extras/symphony-plane-ce/README.md` is the canonical reference for Plane API quirks; do not duplicate it into Symphony's repo. Cross-reference it in the PR body and in module docstrings where helpful.
- After merge, the follow-up tickets PRO-24 (lifecycle hooks) and PRO-25 (`/lfg-symphony` slash command) become unblocked. They depend on this adapter being merged to the fork's `main`.

---

## Sources & References

- Ticket PRO-23: "Plane tracker adapter for Symphony" (Plane workspace `ccm-design`, project `PRO`, module `Symphony`).
- Pre-drafted source kit: `~/Documents/GitHub/personal/obsidian/extras/symphony-plane-ce/`.
- Symphony Tracker behaviour: `elixir/lib/symphony_elixir/tracker.ex`.
- Linear adapter reference: `elixir/lib/symphony_elixir/linear/{adapter,client,issue}.ex`.
- Plane API quirks (verified May 2026): `extras/symphony-plane-ce/README.md` lines 133–185.
- Pre-flight verifier: `extras/symphony-plane-ce/verify-plane-env.sh`.
- Dispatch patch: `extras/symphony-plane-ce/patches/0001-add-plane-tracker-dispatch.patch`.
