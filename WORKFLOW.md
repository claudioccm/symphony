---
# Symphony workflow config — Plane + Compound Engineering edition.
# Place this at the root of the repo Symphony manages, then run:
#   cd $SYMPHONY_DIR/elixir && mix symphony.run --workflow path/to/WORKFLOW.md
#
# NOTE: For PRO-24 verification, codex.command is intentionally `echo` (no-op) so the hook
# lifecycle can be exercised end-to-end without any state changes on Plane cards. PRO-25
# swaps `command` back to `claude` and restores the args block for the real /lfg-symphony
# pipeline.

tracker:
  kind: plane
  # Symphony only spawns attempts when an issue is in one of these states.
  # "Needs Decision" is intentionally excluded — that's the async-question pause state.
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Cancelled
    - Duplicate
  # Module scoping is configured via env: PLANE_MODULE_NAME (or PLANE_MODULE_ID).
  # When set, Symphony only sees issues that belong to that module within the project —
  # useful for running an experiment inside a shared "Projects" project without picking
  # up unrelated cards.

agent:
  # Hard cap across all in-flight cards. Tune to your tolerance for parallel agent runs.
  max_concurrent_agents: 4
  # Override per state if needed. Example: only run two attempts at a time when freshly picked
  # up, but allow more on cards already In Progress.
  max_concurrent_agents_by_state:
    Todo: 2
    "In Progress": 4
  # Cap turns per attempt. Lfg-symphony's pipeline rarely needs more than ~10.
  max_turns: 20

hooks:
  # Each hook is invoked through `lib/symphony-env.sh`, which derives the SYMPHONY_*
  # env vars (workspace, identifier, project UUID, issue UUID) that upstream Symphony
  # does NOT inject natively. The shim caches Plane API lookups under
  # $TMPDIR/symphony-hook-cache so the per-hook overhead is one HTTP call after warmup.
  # Absolute paths so this WORKFLOW.md is portable across the fork's worktrees;
  # operators on other machines must edit these to match their $HOME.
  after_create: /Users/claudiomendonca/.claude/symphony-hooks/lib/symphony-env.sh /Users/claudiomendonca/.claude/symphony-hooks/hooks/after_create.sh
  before_run: /Users/claudiomendonca/.claude/symphony-hooks/lib/symphony-env.sh /Users/claudiomendonca/.claude/symphony-hooks/hooks/before_run.sh
  after_run: /Users/claudiomendonca/.claude/symphony-hooks/lib/symphony-env.sh /Users/claudiomendonca/.claude/symphony-hooks/hooks/after_run.sh
  before_remove: /Users/claudiomendonca/.claude/symphony-hooks/lib/symphony-env.sh /Users/claudiomendonca/.claude/symphony-hooks/hooks/before_remove.sh
  timeout_ms: 60000

codex:
  # PRO-25: codex.command runs a Codex App Server protocol bridge (bin/claude-bridge.sh)
  # that translates JSON-RPC <-> `claude -p`. Symphony spawns this via `bash -lc` with cwd
  # set to the per-card workspace (a checkout of this repo), so the relative path resolves.
  # Symphony's WORKFLOW.md schema does NOT read an `args:` field; the bridge fills the gap.
  command: bin/claude-bridge.sh
  approval_policy: never
  thread_sandbox: workspace-write
---

You are working on a Plane card managed by Symphony.

Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
URL: {{ issue.url }}

Workspace: {{ workspace.path }}
Branch:    {{ workspace.branch }} (already checked out — do NOT switch branches)
Attempt:   {{ attempt }}

Card description:
{% if issue.description %}
{{ issue.description }}
{% else %}
(No description provided.)
{% endif %}

Recent ticket activity (read this carefully — it includes any prior agent questions and human
answers from the "Needs Decision" pause/resume protocol):
{% include_file ".symphony/ticket-thread.md" %}

Run the `/lfg-symphony` command. It will:
  1. Plan the work via `ce-plan`.
  2. Implement via `ce-work`, opening a PR against the `dev` branch.
  3. Review via `ce-code-review` autofix mode.
  4. Resolve residual findings via `ce-resolve-pr-feedback`.
  5. Auto-merge to `dev` once CI is green.

If you hit ambiguity that you cannot resolve from this card, the description, the ticket
thread, or `docs/solutions/`: post a `❓ NEEDS DECISION` comment with options + a
Recommended choice, set the card state to `Needs Decision`, and exit the attempt cleanly.
The human will reply via the next ticket comment and flip the card back to `In Progress`;
your next attempt will see their answer in the ticket thread above.

Never call `AskUserQuestion`. Never merge to `main`.
