---
title: "fix: AgentRunner accepts %Plane.Issue{} (PRO-34)"
type: fix
status: active
date: 2026-05-03
---

# fix: AgentRunner accepts %Plane.Issue{} (PRO-34)

## Summary

Mirror the PRO-32 orchestrator fix in `agent_runner.ex`: add a `PlaneIssue` alias plus an `is_issue/1` `defguardp`, then convert every `%Issue{...} = issue` head in `AgentRunner` to a map-shape pattern guarded by `is_issue(issue)`. After this change, `AgentRunner.run/3` accepts both `%SymphonyElixir.Linear.Issue{}` and `%SymphonyElixir.Plane.Issue{}` so the live PRO-25/PRO-33 Plane dispatch path no longer crashes with `FunctionClauseError` in `issue_context/1`.

---

## Problem Frame

PRO-32 already shipped the dual-issue fix to `orchestrator.ex` (commit `458ad26` on `claudioccm/symphony`). `agent_runner.ex` was missed in that pass — its clauses still pattern-match exclusively on `%SymphonyElixir.Linear.Issue{}`. With Symphony booted under `codex.command=claude` (PRO-25 setup), dispatching a real Plane card (PRO-33) into `AgentRunner.run/3` raises `FunctionClauseError` at `issue_context/1` because no clause head matches a `%SymphonyElixir.Plane.Issue{}` value. The bug is purely a missed sibling site — the surrounding code already treats the two structs as interchangeable by shape.

---

## Requirements

- R1. `AgentRunner.run/3` accepts both `%SymphonyElixir.Linear.Issue{}` and `%SymphonyElixir.Plane.Issue{}` without raising.
- R2. The fix mirrors PRO-32's shape exactly: alias `SymphonyElixir.Plane.Issue, as: PlaneIssue` and a `defguardp is_issue/1` matching either struct.
- R3. `mix test` is green after the change.
- R4. With Symphony booted under PRO-25 (`codex.command=claude`), dispatching PRO-33 from Plane reaches the codex.command spawn step instead of crashing in `AgentRunner`.
- R5. The PR description captures the audit conclusion for `elixir/lib/symphony_elixir/tracker/memory.ex` (Linear-only by design; no fix needed).
- R6. No new public API and no behavioral change for the Linear-only path.

---

## Scope Boundaries

- Out of scope: introducing a shared `Issue` protocol or behaviour (PRO-32 deliberately chose duck-typed map patterns + `is_issue/1`; this PR matches that style).
- Out of scope: any change to `linear/client.ex` — `%Issue{}` there is the Linear adapter's own constructor and is correctly Linear-specific.
- Out of scope: refactoring `tracker/memory.ex` to support Plane — the audit below shows Plane issues never flow through it; the in-memory tracker is dev/test scaffolding for Linear-shape fixtures only.
- Out of scope: changing how `issue_state_fetcher` or `Tracker.fetch_issue_states_by_ids/1` returns results — only the destructure inside `AgentRunner` changes.

---

## Context & Research

### Relevant Code and Patterns

- `elixir/lib/symphony_elixir/orchestrator.ex` (PRO-32 reference, commit `458ad26`):
  - Lines 10-12: alias trio (`{... Tracker, Workspace}`, `Linear.Issue`, `Plane.Issue, as: PlaneIssue`).
  - Lines 14-22: `@type any_issue` typedoc + `defguardp is_issue(value) when is_struct(value, Issue) or is_struct(value, PlaneIssue)`.
  - Throughout: `%{id: issue_id} = issue when is_issue(issue) and is_binary(issue_id)` is the canonical replacement shape; bare `%Issue{} = refreshed_issue` in nested matches becomes `refreshed_issue when is_issue(refreshed_issue)`.
- `elixir/lib/symphony_elixir/plane/issue.ex`: `defstruct` mirrors `Linear.Issue` field-for-field (`:id`, `:identifier`, `:title`, `:state`, etc.), which is why duck-typed map-shape matching is safe.
- `elixir/lib/symphony_elixir/agent_runner.ex` — the file under change. The five sites that need to flip are:
  - Line 8 — alias line (currently `alias SymphonyElixir.{Config, Linear.Issue, PromptBuilder, Tracker, Workspace}`).
  - Line 55 — `defp send_codex_update(recipient, %Issue{id: issue_id}, message)` head.
  - Line 63 — `defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace)` head.
  - Lines 147 + 149 — `defp continue_with_issue?(%Issue{id: issue_id} = issue, ...)` head and the nested `{:ok, [%Issue{} = refreshed_issue | _]}` match inside it.
  - Line 200 — `defp issue_context(%Issue{id: issue_id, identifier: identifier})` head.

### Audit: `elixir/lib/symphony_elixir/tracker/memory.ex`

Audited as part of this work (recorded here so the PR description can reference it):

- The module aliases only `SymphonyElixir.Linear.Issue` and matches `%Issue{state: state}`, `%Issue{id: id}`, and `match?(%Issue{}, &1)` in three sites.
- It is the in-memory `@behaviour SymphonyElixir.Tracker` adapter, selected via the `"memory"` tracker config branch (`tracker.ex` line 42) — used by tests (`extensions_test.exs`, `core_test.exs`) and local dev only.
- Issue values come from the `:memory_tracker_issues` application env, which is only ever populated in tests with `%Linear.Issue{}` fixtures. Plane issues flow through the live Plane adapter, never through `Tracker.Memory`.
- **Audit conclusion:** Linear-only by design. No code change needed in this PR. The PR description will state this explicitly so it isn't re-discovered later.

### Institutional Learnings

- PRO-32 commit `458ad26` (claudioccm/symphony) is the authoritative shape for dual-tracker issue handling. Re-using its alias name (`PlaneIssue`), guard name (`is_issue/1`), and pattern style (`%{id: issue_id} = issue when is_issue(issue) and is_binary(issue_id)`) keeps the codebase consistent and lets a future protocol/behaviour migration grep for one shape, not several.

---

## Key Technical Decisions

- **Mirror PRO-32 verbatim, do not invent a new abstraction.** Use the same `alias ... as: PlaneIssue`, the same `defguardp is_issue/1`, the same map-shape replacement pattern. Rationale: scope discipline, reviewer pattern-recognition, and a single search target if/when this is later promoted to a shared behaviour.
- **No `@type any_issue` in `agent_runner.ex`.** PRO-32 added it in the orchestrator partly because that module also exposes `should_dispatch_issue_for_test/2` and other typed helpers. `AgentRunner.run/3` already takes `map()` in its `@spec`, so introducing the typedoc here would be net-new noise rather than a mirror. Implementer may revisit if review prefers full parity — see Open Questions.
- **Leave `linear/client.ex` untouched.** The `%Issue{}` patterns there construct Linear-shaped responses from the GraphQL client; that struct identity is correct, not a bug.
- **Leave `tracker/memory.ex` untouched in this PR.** See audit above — Plane issues never reach it. Documenting in the PR satisfies R5 without expanding scope.

---

## Open Questions

### Resolved During Planning

- *Should we add an `@type any_issue` typedoc?* — No. AgentRunner's public `@spec` is already `map()`, and no internal typed helper would benefit from it. Reviewer can request it; trivial to add if so.
- *Should `tracker/memory.ex` get the same fix?* — No. Audit confirms it never sees Plane issues. PR description will note this explicitly.

### Deferred to Implementation

- Whether to also place the `defguardp is_issue/1` near the top of the module (as in `orchestrator.ex`) or just before its first use. Mirror the orchestrator's placement for consistency unless the implementer finds a reason to differ.

---

## Implementation Units

- U1. **Add `PlaneIssue` alias and `is_issue/1` defguardp**

**Goal:** Introduce the dual-issue scaffolding in `AgentRunner` so subsequent function heads can guard on `is_issue/1`.

**Requirements:** R2, R6

**Dependencies:** None

**Files:**
- Modify: `elixir/lib/symphony_elixir/agent_runner.ex`

**Approach:**
- Replace the single alias line at line 8 with a trio matching `orchestrator.ex` lines 10-12:
  - Keep `alias SymphonyElixir.{Config, PromptBuilder, Tracker, Workspace}` (drop `Linear.Issue` from the brace group).
  - Add `alias SymphonyElixir.Linear.Issue` on its own line.
  - Add `alias SymphonyElixir.Plane.Issue, as: PlaneIssue` on its own line.
- Add `defguardp is_issue(value) when is_struct(value, Issue) or is_struct(value, PlaneIssue)` in the same relative position the orchestrator uses (just above the module attributes / first function), so future readers can grep one location across both files.
- Do not modify any function bodies in this unit — that's U2's job. Compile only; no behavior change yet.

**Patterns to follow:**
- `elixir/lib/symphony_elixir/orchestrator.ex` lines 10-12 (alias trio) and lines 21-22 (`defguardp`).

**Test scenarios:**
- Test expectation: none -- this unit is pure scaffolding (alias + guard introduction). No call site changes yet, so existing tests must continue to pass unchanged. Verification is "compiles + `mix test` still green at this checkpoint."

**Verification:**
- `mix compile` succeeds with no new warnings.
- `mix test` remains green (no behavioral change yet).

---

- U2. **Convert the five `%Issue{}` clause heads/matches to map-shape + `is_issue/1` guards**

**Goal:** Make every clause in `agent_runner.ex` that currently matches `%Issue{}` accept both Linear and Plane issues by switching to map-shape patterns gated on `is_issue/1`. This is the unit that fixes the live PRO-33 crash.

**Requirements:** R1, R3, R4, R6

**Dependencies:** U1 (the alias and `defguardp` must exist first)

**Files:**
- Modify: `elixir/lib/symphony_elixir/agent_runner.ex`
- Test: `elixir/test/symphony_elixir/core_test.exs` (existing AgentRunner tests must keep passing — no new test file is created in this PR; see Test scenarios for why)

**Approach:**
Convert each of the five sites in order. The replacement shape mirrors PRO-32 exactly:

1. **Line 55** — `defp send_codex_update(recipient, %Issue{id: issue_id}, message) when is_binary(issue_id) and is_pid(recipient)` → `defp send_codex_update(recipient, %{id: issue_id} = issue, message) when is_issue(issue) and is_binary(issue_id) and is_pid(recipient)`. (The unused-variable `issue` may need an underscore prefix if the compiler warns; mirror whichever form orchestrator.ex uses for the analogous case.)
2. **Line 63** — `defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace) when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace)` → `defp send_worker_runtime_info(recipient, %{id: issue_id} = issue, worker_host, workspace) when is_issue(issue) and is_binary(issue_id) and is_pid(recipient) and is_binary(workspace)`.
3. **Line 147** — `defp continue_with_issue?(%Issue{id: issue_id} = issue, issue_state_fetcher) when is_binary(issue_id)` → `defp continue_with_issue?(%{id: issue_id} = issue, issue_state_fetcher) when is_issue(issue) and is_binary(issue_id)`.
4. **Line 149** — inside the same function: `{:ok, [%Issue{} = refreshed_issue | _]} ->` → `{:ok, [refreshed_issue | _]} when is_issue(refreshed_issue) ->` (note: `when` on a `case` clause is supported in Elixir; if the surrounding shape makes that awkward, fall back to a `cond do is_issue(refreshed_issue) ->` pattern as orchestrator.ex does in similar spots — pick whichever the orchestrator uses for its analog at line 762).
5. **Line 200** — `defp issue_context(%Issue{id: issue_id, identifier: identifier})` → `defp issue_context(%{id: issue_id, identifier: identifier} = issue) when is_issue(issue)`.

After conversion, leave the fallback `defp continue_with_issue?(issue, _issue_state_fetcher), do: {:done, issue}` head intact — it still serves as the "issue without a binary id" catch-all and does not need a guard change.

**Patterns to follow:**
- `elixir/lib/symphony_elixir/orchestrator.ex` analogous sites — particularly the `defp issue_context(%{id: issue_id, identifier: identifier} = issue) when is_issue(issue)` at line 1071 (direct mirror of U2 site 5) and the `{:ok, [refreshed_issue | _]} when is_issue(refreshed_issue)` shape around line 762 (direct mirror of U2 site 4).

**Test scenarios:**
- Happy path (existing): all current `core_test.exs` `AgentRunner.run/3` tests (lines 1059, 1147, 1226, 1337, 1454) continue to pass with `%Linear.Issue{}` fixtures — proves Linear behavior is unchanged.
- Happy path (new coverage, only if a Plane-shaped AgentRunner test does not already exist): one direct-call test that invokes `AgentRunner.run/3` (or, if `run/3` is too heavy because of `Workspace.create_for_issue/2` side effects, a direct call to `issue_context/1` and `continue_with_issue?/2` via a small test helper) with a `%SymphonyElixir.Plane.Issue{id: "plane-1", identifier: "PRO-33", state: "In Progress"}` fixture and asserts no `FunctionClauseError` is raised. Implementer decides whether to test through `run/3` (full path, heavier setup) or at the helper level (lighter, exercises the same clause heads). If `core_test.exs` already has a Plane-issue path covering AgentRunner, no new test is required — `mix test` green is sufficient.
- Edge case: `continue_with_issue?/2` called with an `issue` whose `id` is not a binary (e.g., `nil`) still falls through to the catch-all clause and returns `{:done, issue}`. Verify the existing fallback head at the current line 164 still handles this — no new test needed if existing tests cover it.
- Integration scenario: live repro path described in the ticket — Symphony booted with `codex.command=claude`, Plane card dispatched, control reaches the codex.command spawn step. This is verified manually by the implementer (see Verification) since it's an end-to-end smoke that the unit-test layer can't realistically reproduce.

**Verification:**
- `mix compile --warnings-as-errors` succeeds.
- `mix test` is green (R3).
- Manual smoke: with PRO-25's `codex.command=claude` setup, dispatching PRO-33 from Plane no longer raises `FunctionClauseError` at `issue_context/1` and AgentRunner reaches the codex.command spawn step (R4). The orchestrator already accepts the Plane issue (PRO-32 shipped), so this verification is specifically about AgentRunner's frame in the stack trace.

---

## System-Wide Impact

- **Interaction graph:** AgentRunner is called from `orchestrator.ex` (already PRO-32-fixed) and from tests. No upstream call site needs to change because `run/3`'s `@spec` is already `map()`.
- **Error propagation:** The change converts `FunctionClauseError`-on-Plane-issue into normal success-or-error flow. The error paths inside `run_on_worker_host` and `do_run_codex_turns` remain identical.
- **State lifecycle risks:** None. No persisted state, caches, or partial-write surfaces are touched.
- **API surface parity:** This brings AgentRunner into parity with Orchestrator (PRO-32). After this PR, the only remaining `%Linear.Issue{}`-only sites in the orchestration path are intentional: `linear/client.ex` (Linear adapter, correct) and `tracker/memory.ex` (dev/test, audited above).
- **Integration coverage:** Manual end-to-end smoke against a live Plane card (PRO-33) is the integration check that mocks alone won't prove. Recorded under U2 verification.
- **Unchanged invariants:** `AgentRunner.run/3`'s public spec, return shape, retry behavior, worker-host selection, `codex_update_recipient` message contract (`{:codex_worker_update, issue_id, message}`, `{:worker_runtime_info, issue_id, info}`), and turn-loop termination all stay identical for Linear callers.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Compiler warning on the unused-variable `issue` parameter introduced into clause heads that previously discarded it (sites 1 and 2). | Underscore-prefix the binding (`= _issue`) only if a warning fires; otherwise leave it as `issue`. Mirror whichever form `orchestrator.ex` uses for its analogous heads. |
| Subtle change to clause-head matching: the new map-shape `%{id: issue_id} = issue` matches *any* map with an `:id` key, with the `is_issue/1` guard narrowing it back to the two structs. A typo or accidentally-loosened guard could let plain maps through. | The `is_issue/1` guard is identical to PRO-32's. Rely on `mix test` plus the existing `AgentRunner.run/3` tests (which pass `%Linear.Issue{}` fixtures) to prove the narrowing still holds. |
| `case` clauses with `when` guards (U2 site 4) sometimes need a slightly different shape than `def` clauses. | If the direct rewrite triggers a syntax issue, fall back to whichever form `orchestrator.ex` uses at its analogous case site (~line 762). Both forms are equivalent; pick the one already in the codebase. |
| `mix test` could surface latent assumptions (e.g., a test that pattern-matches the structure of a returned issue and inadvertently relied on the `%Issue{}` clause head). | Run the full suite, not just AgentRunner-adjacent files. If a failure is unrelated to this change, file separately rather than expanding scope. |

---

## Documentation / Operational Notes

- PR description must include the `tracker/memory.ex` audit conclusion (R5): "Audited `elixir/lib/symphony_elixir/tracker/memory.ex` — its three `%Issue{}` sites are Linear-specific by design. The in-memory adapter is dev/test scaffolding fed by `:memory_tracker_issues` config, which only ever holds `%Linear.Issue{}` fixtures. Plane issues flow through the live Plane adapter and never reach `Tracker.Memory`. No fix needed."
- Reference PRO-32 commit `458ad26` (claudioccm/symphony) in the PR body so reviewers can diff the shapes side-by-side.
- No runbook / monitoring changes. No feature flag.

---

## Sources & References

- Ticket: PRO-34 (Plane).
- Reference fix: PRO-32, commit `458ad26` on `claudioccm/symphony` — `elixir/lib/symphony_elixir/orchestrator.ex`.
- Live repro context: PRO-25 (`codex.command=claude` boot) + PRO-33 (Plane card dispatched into AgentRunner).
- Code under change: `elixir/lib/symphony_elixir/agent_runner.ex`.
- Audited but not changed: `elixir/lib/symphony_elixir/linear/client.ex` (Linear adapter, correctly Linear-typed), `elixir/lib/symphony_elixir/tracker/memory.ex` (dev/test, never sees Plane issues).
- Mirror struct: `elixir/lib/symphony_elixir/plane/issue.ex` (field-for-field shape parity with `linear/issue.ex` is what makes the duck-typed map pattern safe).
