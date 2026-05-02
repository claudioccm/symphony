defmodule SymphonyElixir.Plane.Client do
  @moduledoc """
  Thin HTTP wrapper over the Plane REST API. Reads auth + workspace from env:

    * `PLANE_API_KEY`            — bearer token
    * `PLANE_WORKSPACE_SLUG`     — workspace slug
    * `PLANE_BASE_URL`           — defaults to https://api.plane.so

  All functions return `{:ok, payload}` or `{:error, term}`. Pagination beyond the first page
  is not implemented in this stub — extend `list_work_items/2` if your projects exceed 100
  active issues.
  """

  @default_base_url "https://api.plane.so"
  @per_page 100

  @spec base_url() :: String.t()
  def base_url, do: System.get_env("PLANE_BASE_URL", @default_base_url)

  @spec workspace_slug() :: String.t()
  def workspace_slug do
    System.get_env("PLANE_WORKSPACE_SLUG") ||
      raise "PLANE_WORKSPACE_SLUG not set"
  end

  @spec api_key() :: String.t()
  def api_key do
    System.get_env("PLANE_API_KEY") ||
      raise "PLANE_API_KEY not set"
  end

  defp headers do
    [
      {"X-API-Key", api_key()},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp ws_url(path), do: "#{base_url()}/api/v1/workspaces/#{workspace_slug()}#{path}"

  @doc "List all projects in the workspace."
  @spec list_projects() :: {:ok, [map()]} | {:error, term()}
  def list_projects do
    get(ws_url("/projects/"))
    |> map_results()
  end

  @doc "Resolve a project UUID by its short identifier (e.g. \"CCM\")."
  @spec project_id_by_identifier(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def project_id_by_identifier(identifier) do
    case list_projects() do
      {:ok, projects} ->
        case Enum.find(projects, fn p -> Map.get(p, "identifier") == identifier end) do
          nil -> {:error, :not_found}
          %{"id" => id} -> {:ok, id}
        end

      err ->
        err
    end
  end

  @doc "List all states for a project."
  @spec list_states(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_states(project_id) do
    get(ws_url("/projects/#{project_id}/states/"))
    |> map_results()
  end

  @doc "List all labels for a project."
  @spec list_labels(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_labels(project_id) do
    get(ws_url("/projects/#{project_id}/labels/"))
    |> map_results()
  end

  @doc "List all modules for a project. Plane uses 'modules' for sub-project / feature-area scoping."
  @spec list_modules(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_modules(project_id) do
    get(ws_url("/projects/#{project_id}/modules/"))
    |> map_results()
  end

  @doc "Resolve a module UUID by its name within a project."
  @spec module_id_by_name(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def module_id_by_name(project_id, name) do
    case list_modules(project_id) do
      {:ok, modules} ->
        case Enum.find(modules, fn m -> Map.get(m, "name") == name end) do
          nil -> {:error, :not_found}
          %{"id" => id} -> {:ok, id}
        end

      err ->
        err
    end
  end

  @doc """
  List work items belonging to a module. The `module-issues/` endpoint returns full work-item
  payloads (NOT join records — only the POST response has those), already scoped to the module.
  Accepts the same `state=<uuid>` filter as the bare work-items endpoint.

  Plane's work-items endpoint silently ignores `module_ids=` / `module=` query params on cloud
  Plane (verified May 2026), so this is the only authoritative way to list module-scoped work.
  """
  @spec list_module_work_items(String.t(), String.t(), [String.t()]) ::
          {:ok, [map()]} | {:error, term()}
  def list_module_work_items(project_id, module_id, state_names \\ []) do
    state_query =
      case state_names do
        [] ->
          ""

        names ->
          with {:ok, states} <- list_states(project_id) do
            states
            |> Enum.filter(fn s -> Map.get(s, "name") in names end)
            |> Enum.map(&"state=#{&1["id"]}")
            |> Enum.join("&")
          else
            _ -> ""
          end
      end

    parts = ["per_page=#{@per_page}", state_query] |> Enum.reject(&(&1 == ""))
    query = "?" <> Enum.join(parts, "&")

    get(ws_url("/projects/#{project_id}/modules/#{module_id}/module-issues/#{query}"))
    |> map_results()
  end

  @doc """
  Add work items to a module. Plane drops `module_ids` set at work-item create time, so this
  is the only way to associate cards with a module programmatically.
  """
  @spec add_issues_to_module(String.t(), String.t(), [String.t()]) ::
          {:ok, [map()]} | {:error, term()}
  def add_issues_to_module(project_id, module_id, work_item_uuids) when is_list(work_item_uuids) do
    post(
      ws_url("/projects/#{project_id}/modules/#{module_id}/module-issues/"),
      %{issues: work_item_uuids}
    )
  end

  @doc """
  List work items for a project, optionally filtered by state name(s) and/or module.

  Options:
    * `:states`    — list of state names (resolved to UUIDs server-side via `?state=uuid` params)
    * `:module_id` — restrict to a single module. Routes through `list_module_work_items/3`,
      which uses the module-issues endpoint — the only place module scoping actually works
      on cloud Plane.

  Both filters are optional and combine with AND semantics.
  """
  @spec list_work_items(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_work_items(project_id, opts \\ []) do
    state_names = Keyword.get(opts, :states, [])
    module_id = Keyword.get(opts, :module_id)

    case module_id do
      nil ->
        list_work_items_unscoped(project_id, state_names)

      mid ->
        list_module_work_items(project_id, mid, state_names)
    end
  end

  defp list_work_items_unscoped(project_id, state_names) do
    state_query =
      case state_names do
        [] ->
          ""

        names ->
          with {:ok, states} <- list_states(project_id) do
            states
            |> Enum.filter(fn s -> Map.get(s, "name") in names end)
            |> Enum.map(&"state=#{&1["id"]}")
            |> Enum.join("&")
          else
            _ -> ""
          end
      end

    parts = ["per_page=#{@per_page}", state_query] |> Enum.reject(&(&1 == ""))
    query = "?" <> Enum.join(parts, "&")

    get(ws_url("/projects/#{project_id}/work-items/#{query}"))
    |> map_results()
  end

  @doc "Fetch a single work item by UUID."
  @spec get_work_item(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_work_item(project_id, work_item_id) do
    get(ws_url("/projects/#{project_id}/work-items/#{work_item_id}/"))
  end

  @doc "Patch a work item — typically used to move state."
  @spec patch_work_item(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def patch_work_item(project_id, work_item_id, body) do
    patch(ws_url("/projects/#{project_id}/work-items/#{work_item_id}/"), body)
  end

  @doc "Post a comment on a work item. Body should be HTML-formatted."
  @spec create_comment(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def create_comment(project_id, work_item_id, comment_html) do
    post(
      ws_url("/projects/#{project_id}/work-items/#{work_item_id}/comments/"),
      %{comment_html: comment_html}
    )
  end

  @doc "Resolve a state UUID by name within a project."
  @spec state_id_by_name(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def state_id_by_name(project_id, name) do
    case list_states(project_id) do
      {:ok, states} ->
        case Enum.find(states, fn s -> Map.get(s, "name") == name end) do
          nil -> {:error, :not_found}
          %{"id" => id} -> {:ok, id}
        end

      err ->
        err
    end
  end

  # ---------- HTTP primitives ----------

  defp get(url), do: request(:get, url, nil)
  defp post(url, body), do: request(:post, url, body)
  defp patch(url, body), do: request(:patch, url, body)

  defp request(method, url, body) do
    base_opts =
      [method: method, url: url, headers: headers(), retry: false]
      |> maybe_add_body(body)

    extra_opts = Application.get_env(:symphony_elixir, :plane_req_options, [])
    opts = Keyword.merge(base_opts, extra_opts)

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp maybe_add_body(opts, nil), do: opts
  defp maybe_add_body(opts, body), do: Keyword.put(opts, :json, body)

  defp map_results({:ok, %{"results" => results}}) when is_list(results), do: {:ok, results}
  defp map_results({:ok, list}) when is_list(list), do: {:ok, list}
  defp map_results({:ok, _other}), do: {:ok, []}
  defp map_results(err), do: err
end
