---
severity: P3
autofix_class: manual
owner: human
requires_verification: true
title: Run mix pr_body.check against PR #1 body
---

# Run mix pr_body.check against PR #1 body

## Context

`elixir/AGENTS.md` mandates: "PR body must follow `../.github/pull_request_template.md` exactly. Validate PR body locally when needed: `mix pr_body.check --file /path/to/pr_body.md`".

The current PR body at https://github.com/claudioccm/symphony/pull/1 was authored before this rule was checked in this review. It includes a "Plane API quirks" section, a "Test coverage" section, and a "Test plan" checklist — likely close to the template, but not verified.

## Action

```bash
cd /Users/claudiomendonca/Documents/GitHub/symphony-wt/PRO-23
gh pr view https://github.com/claudioccm/symphony/pull/1 --json body --jq .body > /tmp/pro-23-pr-body.md
cd elixir && mix pr_body.check --file /tmp/pro-23-pr-body.md
```

If `pr_body.check` reports drift, edit the PR body via `gh pr edit https://github.com/claudioccm/symphony/pull/1 --body-file ...` to match the template. Do NOT auto-edit — the existing body has hand-curated Plane API quirk documentation that must be preserved.

## Why this isn't auto-applied

PR body edits are externalizing actions (publishing content for human review) and require explicit user approval per project policy.
