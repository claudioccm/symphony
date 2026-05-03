defmodule SymphonyElixir.Plane.Issue do
  @moduledoc """
  Normalized Plane issue representation. Mirrors the shape of `SymphonyElixir.Linear.Issue` so
  the orchestrator can treat both adapters interchangeably.
  """

  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :assignee_id,
    blocked_by: [],
    labels: [],
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          labels: [String.t()],
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @priority_map %{
    "urgent" => 1,
    "high" => 2,
    "medium" => 3,
    "low" => 4,
    "none" => nil
  }

  @doc """
  Build a normalized Issue from a raw Plane work-item payload.

  Caches passed in:
    * `state_lookup` — `%{state_uuid => state_name}`
    * `label_lookup` — `%{label_uuid => label_name}`
    * `project_identifier` — e.g. "CCM", used to build the `IDENT-seq` identifier
    * `workspace_slug` and `project_id` — used to build the URL
  """
  @spec from_payload(map(), map()) :: t()
  def from_payload(payload, ctx) do
    %{
      state_lookup: state_lookup,
      label_lookup: label_lookup,
      project_identifier: project_identifier,
      workspace_slug: workspace_slug,
      project_id: project_id
    } = ctx

    state_uuid = Map.get(payload, "state")
    state_name = Map.get(state_lookup, state_uuid)

    label_ids = Map.get(payload, "label_ids", [])
    label_names = Enum.map(label_ids, &Map.get(label_lookup, &1)) |> Enum.reject(&is_nil/1)

    sequence_id = Map.get(payload, "sequence_id")
    identifier = "#{project_identifier}-#{sequence_id}"

    title = Map.get(payload, "name", "")
    branch_name = synthesize_branch_name(identifier, title)

    %__MODULE__{
      id: Map.get(payload, "id"),
      identifier: identifier,
      title: title,
      description: Map.get(payload, "description_stripped") || Map.get(payload, "description_html"),
      priority: priority_to_int(Map.get(payload, "priority")),
      state: state_name,
      branch_name: branch_name,
      url: build_url(workspace_slug, project_id, Map.get(payload, "id")),
      assignee_id: payload |> Map.get("assignees", []) |> List.first(),
      blocked_by: [],
      labels: label_names,
      assigned_to_worker: true,
      created_at: parse_datetime(Map.get(payload, "created_at")),
      updated_at: parse_datetime(Map.get(payload, "updated_at"))
    }
  end

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}), do: labels

  defp priority_to_int(nil), do: nil
  defp priority_to_int(p) when is_binary(p), do: Map.get(@priority_map, p)
  defp priority_to_int(_), do: nil

  defp synthesize_branch_name(identifier, title) do
    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.split("-")
      |> Enum.take(5)
      |> Enum.join("-")

    "feature/#{identifier}-#{slug}"
  end

  defp build_url(slug, project_id, issue_id) when is_binary(issue_id) do
    "https://app.plane.so/#{slug}/projects/#{project_id}/issues/#{issue_id}"
  end

  defp build_url(_, _, _), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end
