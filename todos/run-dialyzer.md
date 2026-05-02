---
severity: P2
autofix_class: manual
owner: downstream-resolver
requires_verification: true
title: Run mix dialyzer to verify PLT-clean against the new Plane modules
---

# Run mix dialyzer

## Context

`make all` (the CI gate per `elixir/AGENTS.md`) includes `mix dialyzer --format short`. The autofix pass added `@spec` annotations to three previously-undocumented public functions in `SymphonyElixir.Plane.Adapter`:

- `start_link/1` :: `keyword() -> {:ok, pid()} | {:error, term()}`
- `reset_cache/0` :: `() -> :ok`
- `markdown_to_html/1` :: `term() -> String.t()`

Dialyzer was not run in this review because building/loading the PLT is heavy (~minutes) and outside the autofix budget. The specs were authored from the implementation, but dialyzer's success/failure typing may flag callsite mismatches that aren't visible by reading the code (e.g. `Agent.start_link/2` actually returns `:ignore | {:error, {:already_started, pid()}} | ...`).

## Action

```bash
cd /Users/claudiomendonca/Documents/GitHub/symphony-wt/PRO-23/elixir
mix deps.get
mix dialyzer --format short
```

If dialyzer flags any of the three new specs:
- For `start_link/1`: widen to `Agent.on_start()` (or `{:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}`).
- For `reset_cache/0`: confirm `Agent.update/2` always returns `:ok` (it does in current Agent — narrow if dialyzer disagrees).
- For `markdown_to_html/1`: should be safe, but dialyzer may demand `String.t() | any()` or similar.

## Why this isn't auto-applied

Dialyzer requires PLT compile (~3-5 min on first run) and is too slow to gate on inside the autofix loop. Better as a Step 4 manual verification before merge.
