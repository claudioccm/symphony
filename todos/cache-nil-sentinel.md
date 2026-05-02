---
severity: P3
autofix_class: gated_auto
owner: downstream-resolver
requires_verification: false
title: Plane.Adapter cache treats nil values as cache misses (perf only)
---

# Plane.Adapter cache treats nil values as cache misses

## Context

In `elixir/lib/symphony_elixir/plane/adapter.ex`, `cache_get/2` is implemented as:

```elixir
defp cache_get(key, fallback_fn) do
  ensure_started()

  case Agent.get(@cache_name, &Map.get(&1, key)) do
    nil ->
      case fallback_fn.() do
        {:ok, val} ->
          Agent.update(@cache_name, &Map.put(&1, key, val))
          {:ok, val}

        err ->
          err
      end

    val ->
      {:ok, val}
  end
end
```

`Map.get(map, key)` returns `nil` both when the key is absent AND when the cached value is literally `nil`. The `module_id` cache stores `{:ok, nil}` (= cached value `nil`) when no `PLANE_MODULE_ID` / `PLANE_MODULE_NAME` is configured, so subsequent `module_id/0` calls re-read the env vars on every invocation instead of hitting the cache.

This is a perf nit, not a correctness bug — env reads are cheap. But if the workflow polls every few seconds, this is a steady drip of unnecessary `System.get_env/1` calls.

## Suggested fix

Use `Map.fetch/2` to distinguish "absent" from "present-but-nil":

```elixir
defp cache_get(key, fallback_fn) do
  ensure_started()

  case Agent.get(@cache_name, &Map.fetch(&1, key)) do
    {:ok, val} ->
      {:ok, val}

    :error ->
      case fallback_fn.() do
        {:ok, val} ->
          Agent.update(@cache_name, &Map.put(&1, key, val))
          {:ok, val}

        err ->
          err
      end
  end
end
```

## Why this isn't safe_auto

Behavior change: previously the no-module case re-resolved every call (cheap), with the fix it caches `nil` permanently and `Adapter.reset_cache/0` is the only way to pick up a newly-set `PLANE_MODULE_NAME` env var. That's likely fine — the existing tests already call `Adapter.reset_cache()` after `System.put_env("PLANE_MODULE_NAME", ...)` — but it's a contract change that should land deliberately, not as part of an autofix sweep.
