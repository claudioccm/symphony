#### Context

Symphony needs a Plane tracker so we can poll a Plane project (scoped to a Module), normalize work items, post comments, and move states — same surface as the Linear adapter.

#### TL;DR

*Adds `SymphonyElixir.Plane.{Adapter,Client,Issue}` implementing the `Tracker` behaviour against Plane's REST API.*

#### Summary

- New modules at `elixir/lib/symphony_elixir/plane/`: `Adapter` (5 Tracker callbacks + Agent-cached lookups), `Client` (Req wrapper, `retry: false`), `Issue` (normalized struct shape-compatible with `Linear.Issue`).
- `Tracker.adapter/0` returns `Plane.Adapter` when `tracker.kind == "plane"`; `Config.validate_semantics/1` accepts `"plane"` alongside `"linear"` and `"memory"`.
- Three Plane API quirks pinned by regression tests (do NOT "fix" these): module filtering only works via `/modules/<MID>/module-issues/` (NOT `?module_ids=`); work-item creation drops `module_ids`, requires two-step POST then `/module-issues/`; relations endpoint is `/relations/` with body shape `{"issues":[...], "relation_type":"blocked_by"}`.
- Coverage: 301 tests / 0 failures / 2 skipped (live e2e). 100% coverage on `Plane.Adapter` + `Plane.Issue`. `Plane.Client` is in `ignore_modules` (HTTP boundary, parity with `Linear.Client`).
- Live smoke: `fetch_candidate_issues/0` returns exactly `["PRO-23","PRO-24","PRO-25"]`; `create_comment/2` and `update_issue_state/2` both round-trip green against PRO-23.

#### Alternatives

- Use `?module_ids=` on `/work-items/` (matches Plane's docs) — silently returns project-wide unfiltered results. Verified against cloud Plane May 2026; rejected.
- POST work item with `module_ids: [<uuid>]` (matches Plane's docs) — returns 200 OK but the work item is not added to the module. Two-step pattern is the only working approach; rejected.
- Resolve `blocked_by` in this PR via `/relations/` — endpoint shape is documented in the adapter moduledoc; deferred per ticket scope so this PR stays read-mostly.

#### Test Plan

- [x] `make -C elixir all`
- [x] `mix test` green (301/301, 2 skipped live-e2e)
- [x] `mix test --cover` shows 100.00% on Plane.Adapter + Plane.Issue
- [x] `mix compile --warnings-as-errors` clean
- [x] `mix lint` (credo --strict) clean
- [x] `mix format --check-formatted` clean
- [x] `extras/symphony-plane-ce/verify-plane-env.sh` exits 0 with all 7 sections green
- [x] Live `fetch_candidate_issues/0` returns exactly the 3 cards in the Symphony module
- [x] Live `create_comment/2` and `update_issue_state/2` both succeed against PRO-23

Plan: `docs/plans/2026-05-02-001-feat-plane-tracker-adapter-plan.md`
