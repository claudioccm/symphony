defmodule SymphonyElixir.Plane.Adapter do
  @moduledoc """
  Plane.so implementation of the `SymphonyElixir.Tracker` behaviour.

  Caches state and label lookups for the configured project so individual issue normalizations
  don't re-fetch them. Cache lifetime is the lifetime of the BEAM process — restart Symphony to
  invalidate, or extend with a TTL if your label set changes mid-run.

  Required env:
    * PLANE_API_KEY
    * PLANE_WORKSPACE_SLUG
    * PLANE_PROJECT_IDENTIFIER  (e.g. "CCM" — the prefix in CCM-103)
    * PLANE_BASE_URL            (optional; defaults to https://api.plane.so)

  Optional env (sub-project / experiment scoping):
    * PLANE_MODULE_NAME         (resolved to UUID at startup, cached)
    * PLANE_MODULE_ID           (UUID directly; takes precedence over PLANE_MODULE_NAME)

  When neither MODULE var is set, Symphony sees ALL active issues in the project. With one set,
  Symphony only sees issues that belong to that module — safe for experiments inside a shared
  project.

  ## Plane API quirks (verified May 2026)

  Three traps the adapter pins; do NOT "fix" them:

  1. Module filtering does NOT work on `/work-items/`. The bare endpoint silently ignores
     `module_ids`, `module`, and `modules` query params. Module-scoped reads MUST go through
     `/modules/<MID>/module-issues/` (which accepts `?state=<uuid>`).
  2. Work-item creation drops `module_ids` from the body. To put a work item in a module,
     POST the work item, then POST `{"issues": [<uuid>]}` to `/modules/<MID>/module-issues/`.
  3. Relations endpoint is `/relations/` (not `/issue-relations/`); body is
     `{"issues": [<uuid>,...], "relation_type": "blocked_by"}`.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Config
  alias SymphonyElixir.Plane.Issue

  use Agent

  @cache_name __MODULE__.Cache

  # ---------- Caching ----------

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: @cache_name)
  end

  @doc false
  @spec reset_cache() :: :ok
  def reset_cache do
    case Process.whereis(@cache_name) do
      nil -> :ok
      _pid -> Agent.update(@cache_name, fn _ -> %{} end)
    end
  end

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

  defp ensure_started do
    case Process.whereis(@cache_name) do
      nil -> start_link()
      _ -> :ok
    end
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :plane_client_module, SymphonyElixir.Plane.Client)
  end

  # ---------- Project + lookup resolution ----------

  defp project_identifier do
    System.get_env("PLANE_PROJECT_IDENTIFIER") ||
      raise "PLANE_PROJECT_IDENTIFIER not set"
  end

  defp project_id do
    cache_get(:project_id, fn -> client_module().project_id_by_identifier(project_identifier()) end)
  end

  # Resolves the configured module UUID, if any. Returns {:ok, uuid} or {:ok, nil} (no module
  # configured — fetch the whole project). Errors only if a module name is configured but cannot
  # be resolved.
  defp module_id do
    cache_get(:module_id, &resolve_module_id/0)
  end

  defp resolve_module_id do
    direct = System.get_env("PLANE_MODULE_ID")
    name = System.get_env("PLANE_MODULE_NAME")

    cond do
      is_binary(direct) and direct != "" ->
        {:ok, direct}

      is_binary(name) and name != "" ->
        resolve_module_id_by_name(name)

      true ->
        {:ok, nil}
    end
  end

  defp resolve_module_id_by_name(name) do
    with {:ok, pid} <- project_id() do
      client_module().module_id_by_name(pid, name)
    end
  end

  defp state_lookup do
    cache_get(:state_lookup, fn ->
      with {:ok, pid} <- project_id(),
           {:ok, states} <- client_module().list_states(pid) do
        {:ok, Map.new(states, fn s -> {s["id"], s["name"]} end)}
      end
    end)
  end

  defp label_lookup do
    cache_get(:label_lookup, fn ->
      with {:ok, pid} <- project_id(),
           {:ok, labels} <- client_module().list_labels(pid) do
        {:ok, Map.new(labels, fn l -> {l["id"], l["name"]} end)}
      else
        # Labels are optional — failure here is non-fatal.
        _ -> {:ok, %{}}
      end
    end)
  end

  defp normalization_ctx do
    with {:ok, pid} <- project_id(),
         {:ok, slu} <- state_lookup(),
         {:ok, lbu} <- label_lookup() do
      {:ok,
       %{
         state_lookup: slu,
         label_lookup: lbu,
         project_identifier: project_identifier(),
         workspace_slug: client_module().workspace_slug(),
         project_id: pid
       }}
    end
  end

  defp configured_active_states do
    Config.settings!().tracker.active_states || ["Todo", "In Progress"]
  end

  # ---------- Tracker behaviour ----------

  @impl true
  def fetch_candidate_issues do
    fetch_issues_by_states(configured_active_states())
  end

  @impl true
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    with {:ok, pid} <- project_id(),
         {:ok, ctx} <- normalization_ctx(),
         {:ok, mid} <- module_id(),
         {:ok, raw} <- client_module().list_work_items(pid, states: state_names, module_id: mid) do
      issues = Enum.map(raw, &Issue.from_payload(&1, ctx))
      {:ok, issues}
    end
  end

  @impl true
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    with {:ok, pid} <- project_id(),
         {:ok, ctx} <- normalization_ctx() do
      collect_issues(issue_ids, pid, ctx)
    end
  end

  defp collect_issues(issue_ids, pid, ctx) do
    results = Enum.map(issue_ids, &fetch_normalized_issue(&1, pid, ctx))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, issue} -> issue end)}
      {:error, _} = err -> err
    end
  end

  defp fetch_normalized_issue(id, pid, ctx) do
    case client_module().get_work_item(pid, id) do
      {:ok, payload} -> {:ok, Issue.from_payload(payload, ctx)}
      err -> err
    end
  end

  @impl true
  def create_comment(issue_id, body) do
    html = markdown_to_html(body)

    with {:ok, pid} <- project_id(),
         {:ok, _} <- client_module().create_comment(pid, issue_id, html) do
      :ok
    end
  end

  @impl true
  def update_issue_state(issue_id, state_name) do
    with {:ok, pid} <- project_id(),
         {:ok, state_id} <- client_module().state_id_by_name(pid, state_name),
         {:ok, _} <- client_module().patch_work_item(pid, issue_id, %{state: state_id}) do
      :ok
    end
  end

  # ---------- Markdown → HTML ----------

  # Plane stores comments as HTML. This is a deliberately simple transform: paragraphs and code
  # fences only. Replace with `Earmark` (a real markdown renderer) if you need full fidelity.
  @doc false
  @spec markdown_to_html(term()) :: String.t()
  def markdown_to_html(md) when is_binary(md) do
    md
    |> String.split("\n\n", trim: true)
    |> Enum.map_join("\n", &format_block/1)
  end

  def markdown_to_html(_), do: ""

  defp format_block(block) do
    if String.starts_with?(block, "```") do
      inner =
        block
        |> String.replace(~r/^```[a-z]*\n?/m, "")
        |> String.replace(~r/```$/m, "")

      "<pre><code>#{escape_html(inner)}</code></pre>"
    else
      "<p>#{block |> escape_html() |> String.replace("\n", "<br/>")}</p>"
    end
  end

  defp escape_html(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
