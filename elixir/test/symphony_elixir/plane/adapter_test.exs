defmodule SymphonyElixir.Plane.AdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Plane.Adapter
  alias SymphonyElixir.Plane.Issue

  defmodule FakePlaneClient do
    @moduledoc false

    def workspace_slug, do: "ccm-design"

    def project_id_by_identifier(identifier) do
      send(self(), {:project_id_by_identifier_called, identifier})
      get_result(:project_id_by_identifier, {:ok, "project-uuid"})
    end

    def list_states(project_id) do
      send(self(), {:list_states_called, project_id})

      get_result(
        :list_states,
        {:ok,
         [
           %{"id" => "todo-uuid", "name" => "Todo"},
           %{"id" => "ip-uuid", "name" => "In Progress"},
           %{"id" => "done-uuid", "name" => "Done"}
         ]}
      )
    end

    def list_labels(project_id) do
      send(self(), {:list_labels_called, project_id})

      get_result(
        :list_labels,
        {:ok, [%{"id" => "label-1", "name" => "bug"}]}
      )
    end

    def list_modules(project_id) do
      send(self(), {:list_modules_called, project_id})
      get_result(:list_modules, {:ok, [%{"id" => "module-uuid", "name" => "Symphony"}]})
    end

    def module_id_by_name(project_id, name) do
      send(self(), {:module_id_by_name_called, project_id, name})
      get_result(:module_id_by_name, {:ok, "module-uuid"})
    end

    def list_work_items(project_id, opts) do
      send(self(), {:list_work_items_called, project_id, opts})

      get_result(
        :list_work_items,
        {:ok,
         [
           %{
             "id" => "wi-1",
             "sequence_id" => 23,
             "name" => "Issue 23",
             "priority" => "high",
             "state" => "todo-uuid",
             "label_ids" => ["label-1"],
             "assignees" => ["assignee-1"]
           }
         ]}
      )
    end

    def get_work_item(project_id, work_item_id) do
      send(self(), {:get_work_item_called, project_id, work_item_id})

      get_result(
        :get_work_item,
        {:ok,
         %{
           "id" => work_item_id,
           "sequence_id" => 24,
           "name" => "Issue #{work_item_id}",
           "priority" => "medium",
           "state" => "ip-uuid"
         }}
      )
    end

    def state_id_by_name(project_id, state_name) do
      send(self(), {:state_id_by_name_called, project_id, state_name})

      case state_name do
        "Done" -> {:ok, "done-uuid"}
        "Todo" -> {:ok, "todo-uuid"}
        "In Progress" -> {:ok, "ip-uuid"}
        _ -> {:error, :not_found}
      end
    end

    def patch_work_item(project_id, work_item_id, body) do
      send(self(), {:patch_work_item_called, project_id, work_item_id, body})
      get_result(:patch_work_item, {:ok, %{"id" => work_item_id}})
    end

    def create_comment(project_id, work_item_id, html) do
      send(self(), {:create_comment_called, project_id, work_item_id, html})
      get_result(:create_comment, {:ok, %{"id" => "comment-uuid"}})
    end

    defp get_result(key, default) do
      case Process.get({__MODULE__, key}) do
        nil -> default
        result -> result
      end
    end
  end

  setup do
    System.put_env("PLANE_API_KEY", "test-key")
    System.put_env("PLANE_WORKSPACE_SLUG", "ccm-design")
    System.put_env("PLANE_PROJECT_IDENTIFIER", "PRO")
    System.delete_env("PLANE_MODULE_NAME")
    System.delete_env("PLANE_MODULE_ID")

    previous_client = Application.get_env(:symphony_elixir, :plane_client_module)
    Application.put_env(:symphony_elixir, :plane_client_module, FakePlaneClient)

    Adapter.reset_cache()

    on_exit(fn ->
      if previous_client == nil do
        Application.delete_env(:symphony_elixir, :plane_client_module)
      else
        Application.put_env(:symphony_elixir, :plane_client_module, previous_client)
      end

      System.delete_env("PLANE_MODULE_NAME")
      System.delete_env("PLANE_MODULE_ID")
      Adapter.reset_cache()
    end)

    :ok
  end

  describe "tracker dispatch wires plane to Plane.Adapter" do
    test "Tracker.adapter/0 returns Plane.Adapter when tracker.kind is plane" do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "plane",
        tracker_api_token: nil,
        tracker_project_slug: nil
      )

      assert SymphonyElixir.Tracker.adapter() == Adapter
    end

    test "memory adapter still wins when tracker.kind is memory" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "memory")
      assert SymphonyElixir.Tracker.adapter() == SymphonyElixir.Tracker.Memory
    end

    test "linear remains default for tracker.kind: linear" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "linear")
      assert SymphonyElixir.Tracker.adapter() == SymphonyElixir.Linear.Adapter
    end
  end

  describe "fetch_candidate_issues/0" do
    test "with PLANE_MODULE_NAME set, calls list_work_items with module_id (Plane API quirk #1 path)" do
      System.put_env("PLANE_MODULE_NAME", "Symphony")
      Adapter.reset_cache()

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "plane",
        tracker_active_states: ["Todo", "In Progress"]
      )

      assert {:ok, [%Issue{} = issue]} = Adapter.fetch_candidate_issues()
      assert issue.identifier == "PRO-23"
      assert issue.priority == 2
      assert issue.state == "Todo"

      assert_received {:module_id_by_name_called, "project-uuid", "Symphony"}
      assert_received {:list_work_items_called, "project-uuid", opts}
      assert Keyword.get(opts, :module_id) == "module-uuid"
      assert Keyword.get(opts, :states) == ["Todo", "In Progress"]
    end

    test "with no module configured, calls list_work_items with module_id: nil" do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "plane",
        tracker_active_states: ["Todo", "In Progress"]
      )

      assert {:ok, _issues} = Adapter.fetch_candidate_issues()

      assert_received {:list_work_items_called, "project-uuid", opts}
      assert Keyword.get(opts, :module_id) == nil
      refute_received {:module_id_by_name_called, _, _}
    end

    test "with PLANE_MODULE_ID set directly, uses that UUID and skips name lookup" do
      System.put_env("PLANE_MODULE_ID", "direct-module-uuid")
      Adapter.reset_cache()

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "plane",
        tracker_active_states: ["Todo"]
      )

      assert {:ok, _} = Adapter.fetch_candidate_issues()

      assert_received {:list_work_items_called, "project-uuid", opts}
      assert Keyword.get(opts, :module_id) == "direct-module-uuid"
      refute_received {:module_id_by_name_called, _, _}
    end

    test "uses default active_states [Todo, In Progress] when not configured" do
      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "plane",
        tracker_active_states: nil
      )

      assert {:ok, _} = Adapter.fetch_candidate_issues()
      assert_received {:list_work_items_called, _, opts}
      assert Keyword.get(opts, :states) == ["Todo", "In Progress"]
    end

    test "empty result list returns {:ok, []}" do
      Process.put({FakePlaneClient, :list_work_items}, {:ok, []})

      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:ok, []} = Adapter.fetch_candidate_issues()
    end

    test "client error propagates" do
      Process.put({FakePlaneClient, :list_work_items}, {:error, :boom})

      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:error, :boom} = Adapter.fetch_candidate_issues()
    end

    test "module name not found surfaces as :not_found" do
      System.put_env("PLANE_MODULE_NAME", "NoSuchModule")
      Adapter.reset_cache()
      Process.put({FakePlaneClient, :module_id_by_name}, {:error, :not_found})

      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:error, :not_found} = Adapter.fetch_candidate_issues()
    end
  end

  describe "fetch_issues_by_states/1" do
    test "passes the named state list through to the client" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:ok, _} = Adapter.fetch_issues_by_states(["Todo"])

      assert_received {:list_work_items_called, "project-uuid", opts}
      assert Keyword.get(opts, :states) == ["Todo"]
    end
  end

  describe "fetch_issue_states_by_ids/1" do
    test "returns one Issue per id, normalized via from_payload" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:ok, [%Issue{} = i1, %Issue{} = i2]} =
               Adapter.fetch_issue_states_by_ids(["wi-a", "wi-b"])

      assert i1.id == "wi-a"
      assert i2.id == "wi-b"
      assert_received {:get_work_item_called, "project-uuid", "wi-a"}
      assert_received {:get_work_item_called, "project-uuid", "wi-b"}
    end

    test "any client error short-circuits the result" do
      Process.put({FakePlaneClient, :get_work_item}, {:error, :boom})
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:error, :boom} = Adapter.fetch_issue_states_by_ids(["wi-a"])
    end
  end

  describe "create_comment/2" do
    test "passes markdown→HTML transformed body to client" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert :ok = Adapter.create_comment("wi-uuid", "Hello\n\nWorld")

      assert_received {:create_comment_called, "project-uuid", "wi-uuid", html}
      assert html =~ "<p>Hello</p>"
      assert html =~ "<p>World</p>"
    end

    test "code fence becomes <pre><code>" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert :ok = Adapter.create_comment("wi-uuid", "```\nlet x = 1;\n```")

      assert_received {:create_comment_called, _, _, html}
      assert html =~ "<pre><code>"
      assert html =~ "let x = 1;"
    end

    test "HTML-special characters are escaped in <p>" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert :ok = Adapter.create_comment("wi-uuid", "a < b & c > d")

      assert_received {:create_comment_called, _, _, html}
      assert html =~ "&lt;"
      assert html =~ "&gt;"
      assert html =~ "&amp;"
    end

    test "non-binary body becomes empty string (markdown_to_html default)" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert :ok = Adapter.create_comment("wi-uuid", nil)
      assert_received {:create_comment_called, _, _, ""}
    end

    test "client error propagates" do
      Process.put({FakePlaneClient, :create_comment}, {:error, :boom})
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:error, :boom} = Adapter.create_comment("wi-uuid", "body")
    end
  end

  describe "update_issue_state/2" do
    test "resolves state name to UUID, then PATCHes work item" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert :ok = Adapter.update_issue_state("wi-uuid", "Done")

      assert_received {:state_id_by_name_called, "project-uuid", "Done"}
      assert_received {:patch_work_item_called, "project-uuid", "wi-uuid", %{state: "done-uuid"}}
    end

    test "unknown state name surfaces :not_found" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:error, :not_found} = Adapter.update_issue_state("wi-uuid", "NoSuchState")
      refute_received {:patch_work_item_called, _, _, _}
    end

    test "patch failure propagates" do
      Process.put({FakePlaneClient, :patch_work_item}, {:error, :boom})
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:error, :boom} = Adapter.update_issue_state("wi-uuid", "Done")
    end
  end

  describe "raise on missing required env" do
    test "PLANE_PROJECT_IDENTIFIER not set raises" do
      System.delete_env("PLANE_PROJECT_IDENTIFIER")
      Adapter.reset_cache()
      on_exit(fn -> System.put_env("PLANE_PROJECT_IDENTIFIER", "PRO") end)

      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert_raise RuntimeError, ~r/PLANE_PROJECT_IDENTIFIER/, fn ->
        Adapter.fetch_candidate_issues()
      end
    end
  end

  describe "label normalization through adapter pipeline" do
    test "labels are resolved to names via list_labels lookup" do
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:ok, [%Issue{labels: ["bug"]}]} = Adapter.fetch_candidate_issues()
    end

    test "label fetch failure is non-fatal — labels become empty" do
      Process.put({FakePlaneClient, :list_labels}, {:error, :boom})
      Adapter.reset_cache()

      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")

      assert {:ok, [%Issue{labels: []}]} = Adapter.fetch_candidate_issues()
    end
  end

  describe "Agent cache lifecycle" do
    test "start_link starts the cache; reset_cache clears entries" do
      Adapter.reset_cache()
      # First call populates project_id, state_lookup, label_lookup caches
      write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "plane")
      {:ok, _} = Adapter.fetch_candidate_issues()
      assert_received {:project_id_by_identifier_called, "PRO"}

      # Second call: cache hit, no new project_id_by_identifier call
      {:ok, _} = Adapter.fetch_candidate_issues()
      refute_received {:project_id_by_identifier_called, _}

      # After reset, fetches again
      Adapter.reset_cache()
      {:ok, _} = Adapter.fetch_candidate_issues()
      assert_received {:project_id_by_identifier_called, "PRO"}
    end
  end
end
