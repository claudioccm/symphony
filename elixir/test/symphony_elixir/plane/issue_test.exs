defmodule SymphonyElixir.Plane.IssueTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Plane.Issue

  @ctx %{
    state_lookup: %{
      "state-uuid-todo" => "Todo",
      "state-uuid-ip" => "In Progress"
    },
    label_lookup: %{
      "label-uuid-1" => "bug",
      "label-uuid-2" => "feature"
    },
    project_identifier: "PRO",
    workspace_slug: "ccm-design",
    project_id: "project-uuid"
  }

  defp base_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "work-item-uuid-1",
        "sequence_id" => 23,
        "name" => "Plane tracker adapter for Symphony",
        "description_stripped" => "the description",
        "priority" => "high",
        "state" => "state-uuid-todo",
        "label_ids" => ["label-uuid-1"],
        "assignees" => ["user-uuid-1"],
        "created_at" => "2026-05-02T12:00:00.000000Z",
        "updated_at" => "2026-05-02T13:00:00.000000Z"
      },
      overrides
    )
  end

  describe "from_payload/2 priority enum mapping" do
    test "urgent maps to 1" do
      issue = Issue.from_payload(base_payload(%{"priority" => "urgent"}), @ctx)
      assert issue.priority == 1
    end

    test "high maps to 2" do
      issue = Issue.from_payload(base_payload(%{"priority" => "high"}), @ctx)
      assert issue.priority == 2
    end

    test "medium maps to 3" do
      issue = Issue.from_payload(base_payload(%{"priority" => "medium"}), @ctx)
      assert issue.priority == 3
    end

    test "low maps to 4" do
      issue = Issue.from_payload(base_payload(%{"priority" => "low"}), @ctx)
      assert issue.priority == 4
    end

    test "none maps to nil (Plane convention)" do
      issue = Issue.from_payload(base_payload(%{"priority" => "none"}), @ctx)
      assert issue.priority == nil
    end

    test "nil priority maps to nil" do
      issue = Issue.from_payload(base_payload(%{"priority" => nil}), @ctx)
      assert issue.priority == nil
    end

    test "unknown priority string maps to nil" do
      issue = Issue.from_payload(base_payload(%{"priority" => "bogus"}), @ctx)
      assert issue.priority == nil
    end

    test "non-binary priority maps to nil" do
      issue = Issue.from_payload(base_payload(%{"priority" => 7}), @ctx)
      assert issue.priority == nil
    end
  end

  describe "from_payload/2 branch_name synthesis" do
    test "PRO-23 with Plane tracker adapter title yields a feature/pro-23-plane-tracker-adapter slug" do
      issue =
        Issue.from_payload(
          base_payload(%{"sequence_id" => 23, "name" => "Plane tracker adapter for Symphony"}),
          @ctx
        )

      assert issue.identifier == "PRO-23"
      assert issue.branch_name == "feature/PRO-23-plane-tracker-adapter-for-symphony"
    end

    test "title with punctuation, accents, and trailing whitespace slugs cleanly" do
      issue =
        Issue.from_payload(
          base_payload(%{
            "sequence_id" => 99,
            "name" => "  Café & déjà-vu: Plane!  "
          }),
          @ctx
        )

      # Hyphens collapse non-alphanumerics; first 5 hyphen-segments retained.
      assert issue.identifier == "PRO-99"
      assert String.starts_with?(issue.branch_name, "feature/PRO-99-")
      refute issue.branch_name =~ ~r/[^a-zA-Z0-9\/\-]/
    end
  end

  describe "from_payload/2 full struct shape" do
    test "all orchestrator-consumed fields are populated correctly" do
      issue = Issue.from_payload(base_payload(), @ctx)

      assert %Issue{} = issue
      assert issue.id == "work-item-uuid-1"
      assert issue.identifier == "PRO-23"
      assert issue.title == "Plane tracker adapter for Symphony"
      assert issue.description == "the description"
      assert issue.state == "Todo"
      assert issue.url == "https://app.plane.so/ccm-design/projects/project-uuid/issues/work-item-uuid-1"
      assert issue.assignee_id == "user-uuid-1"
      assert issue.labels == ["bug"]
      assert issue.assigned_to_worker == true
      assert issue.blocked_by == []
      assert %DateTime{} = issue.created_at
      assert %DateTime{} = issue.updated_at
    end

    test "blocked_by is always [] in this iteration regardless of payload" do
      issue =
        Issue.from_payload(
          base_payload(%{"blocked_by_ids" => ["a", "b"], "relations" => [%{"x" => 1}]}),
          @ctx
        )

      assert issue.blocked_by == []
    end

    test "labels resolve from label_ids via label_lookup" do
      issue =
        Issue.from_payload(
          base_payload(%{"label_ids" => ["label-uuid-1", "label-uuid-2", "missing"]}),
          @ctx
        )

      assert issue.labels == ["bug", "feature"]
    end

    test "missing description falls back to description_html" do
      issue =
        Issue.from_payload(
          base_payload(%{
            "description_stripped" => nil,
            "description_html" => "<p>html only</p>"
          }),
          @ctx
        )

      assert issue.description == "<p>html only</p>"
    end

    test "missing assignees yields nil assignee_id" do
      issue = Issue.from_payload(base_payload(%{"assignees" => []}), @ctx)
      assert issue.assignee_id == nil
    end

    test "missing id leaves url as nil" do
      issue = Issue.from_payload(base_payload(%{"id" => nil}), @ctx)
      assert issue.url == nil
    end

    test "invalid datetime strings parse to nil" do
      issue =
        Issue.from_payload(
          base_payload(%{"created_at" => "not-a-date", "updated_at" => nil}),
          @ctx
        )

      assert issue.created_at == nil
      assert issue.updated_at == nil
    end

    test "label_names/1 returns the labels list" do
      issue = Issue.from_payload(base_payload(), @ctx)
      assert Issue.label_names(issue) == ["bug"]
    end

    test "unknown state UUID resolves to nil state" do
      issue = Issue.from_payload(base_payload(%{"state" => "unknown"}), @ctx)
      assert issue.state == nil
    end
  end
end
