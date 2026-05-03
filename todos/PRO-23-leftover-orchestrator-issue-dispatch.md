---
severity: P1
autofix_class: manual
owner: human
file: elixir/lib/symphony_elixir/orchestrator.ex
line: (alias + pattern-match site)
ticket: PRO-23 (NOT PRO-24)
status: residual
out_of_scope: true
---

# `orchestrator.ex` aliases `Linear.Issue` so `%Plane.Issue{}` never dispatches

## Problem

`SymphonyElixir.Orchestrator` currently does:

```elixir
alias SymphonyElixir.Linear.Issue
# ...
case work_item do
  %Issue{} = issue -> ...
end
```

Because the `alias Linear.Issue` resolves the unqualified `%Issue{}` pattern to
`%SymphonyElixir.Linear.Issue{}`, and the Plane adapter (PRO-23) emits
`%SymphonyElixir.Plane.Issue{}` structs, the Plane code path silently never matches.
Symphony will appear to fetch candidates from Plane (the adapter runs), but the
orchestrator's per-issue handler effectively no-ops on them.

## Why this is residual to PRO-24

The PRO-24 plan explicitly puts Elixir changes out of scope: "Modifying any Elixir
code in `elixir/lib/symphony_elixir/` — the adapter wiring is complete from PRO-23."
This is a PRO-23 leftover. Fixing it inside PRO-24 would (a) blow scope, and (b)
expand the diff into Elixir code that has zero overlap with the bash-hook work
under review.

It will, however, prevent PRO-25's full `/lfg-symphony` invocation from running
end-to-end against Plane cards. Every PR-25 work-loop attempt will appear to start
(workspace allocated, hooks fire) and immediately exit because the orchestrator
case-clause silently drops the unknown struct.

## Suggested fix (for the separate cleanup ticket)

Either:

1. **Drop the alias and pattern-match on the fully-qualified module names**, with
   one clause per adapter struct:
   ```elixir
   case work_item do
     %SymphonyElixir.Linear.Issue{} = issue -> handle_linear(issue)
     %SymphonyElixir.Plane.Issue{} = issue -> handle_plane(issue)
   end
   ```

2. **Define a `SymphonyElixir.Issue` protocol** that both adapter structs implement,
   and dispatch via the protocol. This is the cleaner long-term shape, since the
   tracker abstraction in PRO-23 already implies a protocol-shaped interface, but
   it's a wider refactor.

(1) is the smaller fix and unblocks PRO-25 immediately. (2) is the right shape if a
third tracker adapter is on the roadmap.

## Action

Open a new Plane card titled
`fix(symphony): orchestrator dispatches all work-items as Linear.Issue` against the
`PRO` project, blocking PRO-25. Reference this todo file in the card body.
