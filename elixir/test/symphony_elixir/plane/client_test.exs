defmodule SymphonyElixir.Plane.ClientTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Plane.Client

  @stub_name __MODULE__.Stub

  setup do
    System.put_env("PLANE_API_KEY", "test-key")
    System.put_env("PLANE_WORKSPACE_SLUG", "ccm-design")
    System.put_env("PLANE_BASE_URL", "https://api.plane.so")

    previous = Application.get_env(:symphony_elixir, :plane_req_options)
    Application.put_env(:symphony_elixir, :plane_req_options, plug: {Req.Test, @stub_name})

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:symphony_elixir, :plane_req_options)
      else
        Application.put_env(:symphony_elixir, :plane_req_options, previous)
      end
    end)

    :ok
  end

  defp request_capture(response_body) do
    test_pid = self()

    Req.Test.stub(@stub_name, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, {:captured,
        %{
          method: conn.method,
          path: conn.request_path,
          query: conn.query_string,
          headers: conn.req_headers,
          body: raw_body
        }})

      Req.Test.json(conn, response_body)
    end)
  end

  describe "auth headers" do
    test "every request includes X-API-Key header" do
      request_capture(%{"results" => []})

      {:ok, _} = Client.list_projects()

      assert_received {:captured, %{headers: headers}}
      assert {"x-api-key", "test-key"} in headers
    end
  end

  describe "list_module_work_items/3 — module-scoping path (Plane API quirk #1 regression guard)" do
    test "uses /modules/<MID>/module-issues/ NOT /work-items/ when scoping to a module" do
      Req.Test.stub(@stub_name, fn conn ->
        cond do
          String.ends_with?(conn.request_path, "/states/") ->
            Req.Test.json(conn, %{
              "results" => [
                %{"id" => "todo-uuid", "name" => "Todo"},
                %{"id" => "ip-uuid", "name" => "In Progress"}
              ]
            })

          true ->
            send(self(), :path_check)

            send(
              self(),
              {:final_call,
               %{
                 method: conn.method,
                 path: conn.request_path,
                 query: conn.query_string
               }}
            )

            Req.Test.json(conn, %{"results" => [%{"id" => "wi-1"}]})
        end
      end)

      assert {:ok, [%{"id" => "wi-1"}]} =
               Client.list_module_work_items("project-uuid", "module-uuid", ["Todo"])

      assert_received {:final_call, info}
      assert info.method == "GET"
      assert info.path =~ "/modules/module-uuid/module-issues/"
      refute info.path =~ "/work-items/"
      assert info.query =~ "state=todo-uuid"
    end

    test "with multiple state names appends repeated ?state=<a>&state=<b> query params" do
      Req.Test.stub(@stub_name, fn conn ->
        cond do
          String.ends_with?(conn.request_path, "/states/") ->
            Req.Test.json(conn, %{
              "results" => [
                %{"id" => "todo-uuid", "name" => "Todo"},
                %{"id" => "ip-uuid", "name" => "In Progress"},
                %{"id" => "review-uuid", "name" => "In Review"}
              ]
            })

          true ->
            send(self(), {:final_query, conn.query_string})
            Req.Test.json(conn, %{"results" => []})
        end
      end)

      assert {:ok, []} =
               Client.list_module_work_items("project-uuid", "module-uuid", [
                 "Todo",
                 "In Progress"
               ])

      assert_received {:final_query, query}
      assert query =~ "state=todo-uuid"
      assert query =~ "state=ip-uuid"
      refute query =~ "state=review-uuid"
    end

    test "with empty state list still produces a valid URL with no trailing & or stray ?" do
      Req.Test.stub(@stub_name, fn conn ->
        send(self(), {:final_url, conn.request_path, conn.query_string})
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, []} = Client.list_module_work_items("project-uuid", "module-uuid", [])

      assert_received {:final_url, path, query}
      assert path =~ "/modules/module-uuid/module-issues/"
      # Either empty query or only per_page; no stray & at start/end
      refute String.starts_with?(query, "&")
      refute String.ends_with?(query, "&")
      assert query =~ "per_page="
    end
  end

  describe "list_work_items/2 — bare project endpoint when no module configured" do
    test "uses /work-items/ when module_id is not set" do
      Req.Test.stub(@stub_name, fn conn ->
        cond do
          String.ends_with?(conn.request_path, "/states/") ->
            Req.Test.json(conn, %{
              "results" => [%{"id" => "todo-uuid", "name" => "Todo"}]
            })

          true ->
            send(self(), {:final_path, conn.request_path, conn.query_string})
            Req.Test.json(conn, %{"results" => [%{"id" => "wi-1"}]})
        end
      end)

      assert {:ok, [%{"id" => "wi-1"}]} =
               Client.list_work_items("project-uuid", states: ["Todo"])

      assert_received {:final_path, path, query}
      assert path =~ "/projects/project-uuid/work-items/"
      refute path =~ "/modules/"
      refute path =~ "/module-issues/"
      assert query =~ "state=todo-uuid"
    end

    test "list_work_items with module_id routes through module-issues path" do
      Req.Test.stub(@stub_name, fn conn ->
        cond do
          String.ends_with?(conn.request_path, "/states/") ->
            Req.Test.json(conn, %{"results" => []})

          true ->
            send(self(), {:final_path, conn.request_path})
            Req.Test.json(conn, %{"results" => []})
        end
      end)

      assert {:ok, []} =
               Client.list_work_items("project-uuid", states: [], module_id: "module-uuid")

      assert_received {:final_path, path}
      assert path =~ "/modules/module-uuid/module-issues/"
    end
  end

  describe "create_comment/3 — markdown comments POST to /work-items/<wid>/comments/" do
    test "posts comment_html body to the correct path" do
      request_capture(%{"id" => "comment-uuid"})

      assert {:ok, %{"id" => "comment-uuid"}} =
               Client.create_comment("project-uuid", "wi-uuid", "<p>Hello</p>")

      assert_received {:captured, info}
      assert info.method == "POST"
      assert info.path =~ "/work-items/wi-uuid/comments/"

      decoded = Jason.decode!(info.body)
      assert decoded == %{"comment_html" => "<p>Hello</p>"}
    end
  end

  describe "patch_work_item/3 — state move PATCHes /work-items/<wid>/" do
    test "PATCHes with state UUID body" do
      request_capture(%{"id" => "wi-uuid", "state" => "state-uuid"})

      assert {:ok, _} =
               Client.patch_work_item("project-uuid", "wi-uuid", %{state: "state-uuid"})

      assert_received {:captured, info}
      assert info.method == "PATCH"
      assert info.path =~ "/work-items/wi-uuid/"
      assert Jason.decode!(info.body) == %{"state" => "state-uuid"}
    end
  end

  describe "state_id_by_name/2" do
    test "returns the UUID matching the named state" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{
          "results" => [
            %{"id" => "todo-uuid", "name" => "Todo"},
            %{"id" => "ip-uuid", "name" => "In Progress"}
          ]
        })
      end)

      assert {:ok, "ip-uuid"} = Client.state_id_by_name("project-uuid", "In Progress")
    end

    test "returns :not_found when name doesn't match" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"results" => [%{"id" => "x", "name" => "Other"}]})
      end)

      assert {:error, :not_found} = Client.state_id_by_name("project-uuid", "Missing")
    end

    test "propagates upstream errors" do
      Req.Test.stub(@stub_name, fn conn ->
        conn = Plug.Conn.put_status(conn, 500)
        Req.Test.json(conn, %{"error" => "boom"})
      end)

      assert {:error, {:http_error, 500, _}} = Client.state_id_by_name("project-uuid", "Todo")
    end
  end

  describe "module_id_by_name/2" do
    test "resolves module name to UUID" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"results" => [%{"id" => "mod-uuid", "name" => "Symphony"}]})
      end)

      assert {:ok, "mod-uuid"} = Client.module_id_by_name("project-uuid", "Symphony")
    end

    test ":not_found when module doesn't exist" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:error, :not_found} = Client.module_id_by_name("project-uuid", "Nope")
    end
  end

  describe "project_id_by_identifier/1" do
    test "returns project UUID by identifier" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{
          "results" => [
            %{"id" => "p1", "identifier" => "PRO"},
            %{"id" => "p2", "identifier" => "OTHER"}
          ]
        })
      end)

      assert {:ok, "p1"} = Client.project_id_by_identifier("PRO")
    end

    test ":not_found for unknown identifier" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:error, :not_found} = Client.project_id_by_identifier("ZZZ")
    end
  end

  describe "add_issues_to_module/3 — Plane API quirk #2 regression guard" do
    test "POSTs {issues: [<uuid>,...]} to /modules/<MID>/module-issues/" do
      request_capture(%{"results" => []})

      assert {:ok, _} =
               Client.add_issues_to_module("project-uuid", "module-uuid", [
                 "wi-1",
                 "wi-2"
               ])

      assert_received {:captured, info}
      assert info.method == "POST"
      assert info.path =~ "/modules/module-uuid/module-issues/"
      assert Jason.decode!(info.body) == %{"issues" => ["wi-1", "wi-2"]}
    end
  end

  describe "error path handling" do
    test "401 unauthorized surfaces as {:error, {:http_error, 401, _}}" do
      Req.Test.stub(@stub_name, fn conn ->
        conn = Plug.Conn.put_status(conn, 401)
        Req.Test.json(conn, %{"error" => "unauthorized"})
      end)

      assert {:error, {:http_error, 401, _}} = Client.list_projects()
    end

    test "429 rate-limited surfaces as {:error, {:http_error, 429, _}} with no retry" do
      counter = :counters.new(1, [])

      Req.Test.stub(@stub_name, fn conn ->
        :counters.add(counter, 1, 1)
        conn = Plug.Conn.put_status(conn, 429)
        Req.Test.json(conn, %{"error" => "rate limited"})
      end)

      assert {:error, {:http_error, 429, _}} = Client.list_projects()
      assert :counters.get(counter, 1) == 1
    end

    test "transport error surfaces as {:error, exception}" do
      Req.Test.stub(@stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, _exception} = Client.list_projects()
    end
  end

  describe "self-hosted PLANE_BASE_URL override" do
    test "honored when PLANE_BASE_URL is changed" do
      System.put_env("PLANE_BASE_URL", "https://plane.internal.example.com")
      on_exit(fn -> System.put_env("PLANE_BASE_URL", "https://api.plane.so") end)

      Req.Test.stub(@stub_name, fn conn ->
        send(self(), {:host, conn.host})
        Req.Test.json(conn, %{"results" => []})
      end)

      {:ok, _} = Client.list_projects()
      assert_received {:host, host}
      assert host == "plane.internal.example.com"
    end
  end

  describe "list_modules/1, list_states/1, list_labels/1, get_work_item/2" do
    test "list_modules hits /projects/<pid>/modules/" do
      request_capture(%{"results" => [%{"id" => "m1"}]})
      assert {:ok, [%{"id" => "m1"}]} = Client.list_modules("project-uuid")
      assert_received {:captured, %{path: path}}
      assert path =~ "/projects/project-uuid/modules/"
    end

    test "list_states hits /projects/<pid>/states/" do
      request_capture(%{"results" => [%{"id" => "s1"}]})
      assert {:ok, [%{"id" => "s1"}]} = Client.list_states("project-uuid")
      assert_received {:captured, %{path: path}}
      assert path =~ "/projects/project-uuid/states/"
    end

    test "list_labels hits /projects/<pid>/labels/" do
      request_capture(%{"results" => [%{"id" => "l1"}]})
      assert {:ok, [%{"id" => "l1"}]} = Client.list_labels("project-uuid")
      assert_received {:captured, %{path: path}}
      assert path =~ "/projects/project-uuid/labels/"
    end

    test "get_work_item hits /projects/<pid>/work-items/<wid>/" do
      request_capture(%{"id" => "wi-1"})
      assert {:ok, %{"id" => "wi-1"}} = Client.get_work_item("project-uuid", "wi-1")
      assert_received {:captured, %{path: path}}
      assert path =~ "/projects/project-uuid/work-items/wi-1/"
    end
  end

  describe "raise on missing required env" do
    test "workspace_slug raises when PLANE_WORKSPACE_SLUG unset" do
      System.delete_env("PLANE_WORKSPACE_SLUG")
      on_exit(fn -> System.put_env("PLANE_WORKSPACE_SLUG", "ccm-design") end)
      assert_raise RuntimeError, ~r/PLANE_WORKSPACE_SLUG/, fn -> Client.workspace_slug() end
    end

    test "api_key raises when PLANE_API_KEY unset" do
      System.delete_env("PLANE_API_KEY")
      on_exit(fn -> System.put_env("PLANE_API_KEY", "test-key") end)
      assert_raise RuntimeError, ~r/PLANE_API_KEY/, fn -> Client.api_key() end
    end

    test "base_url falls back to default when PLANE_BASE_URL unset" do
      System.delete_env("PLANE_BASE_URL")
      on_exit(fn -> System.put_env("PLANE_BASE_URL", "https://api.plane.so") end)
      assert Client.base_url() == "https://api.plane.so"
    end
  end
end
