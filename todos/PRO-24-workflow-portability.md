---
severity: P3
autofix_class: advisory
owner: human
file: WORKFLOW.md
line: 45
ticket: PRO-24
status: wontfix-accepted
---

## Resolution (Step 4)

**Marked `wontfix / accepted`. No changes made.**

### Rationale (mirrors the plan)
- The implementation plan's Key Technical Decisions explicitly chose
  fully-expanded absolute paths in `WORKFLOW.md`, on the rationale that this
  fork is single-developer at this stage.
- The plan's Risks & Dependencies table accepts the trade-off: portability cost
  (other developers must edit four lines after cloning) is documented.
- The PR body documents the manual edit a second developer would need.
- WORKFLOW.md frontmatter (lines 43-44) calls out the limitation in-place.
- Two clean follow-up paths are already noted in the body of this todo (env
  substitution at boot, or an installer script with `sed` substitution); either
  belongs in a separate ticket when the single-developer assumption breaks.

No action required for PRO-24 to merge.

# WORKFLOW.md hard-codes `/Users/claudiomendonca/...` absolute paths

## Problem

`WORKFLOW.md` lines 45-48 reference the hooks via fully-expanded absolute paths:

```yaml
after_create: /Users/claudiomendonca/.claude/symphony-hooks/lib/symphony-env.sh /Users/claudiomendonca/.claude/symphony-hooks/hooks/after_create.sh
```

Anyone else who clones the fork and tries `mix symphony.run --workflow WORKFLOW.md`
will get a hook-invocation failure unless they edit four lines first. The plan
explicitly accepted this trade-off (Key Technical Decision: "store fully-expanded
absolute paths ... since this fork is single-developer at this stage") and the
WORKFLOW.md frontmatter comment (lines 43-44) calls it out, so this is not a defect
against the plan — it is a known scope limitation.

## Suggested fix (when this becomes a real need)

Two reasonable options when the fork goes multi-developer or moves into CI:

1. **Env substitution at boot.** Symphony's WORKFLOW.md loader does not currently expand
   `${HOME}` in hook paths. Add a small pre-processing step (Elixir-side, in the
   workflow loader) that substitutes `${HOME}` and a curated allowlist of env vars
   before passing the strings to the hook dispatcher. Then this file becomes:
   `${HOME}/.claude/symphony-hooks/lib/symphony-env.sh ${HOME}/.claude/symphony-hooks/hooks/after_create.sh`

2. **Installer script with `sed` substitution.** A `bin/install-symphony-hooks.sh` (the
   plan's deferred follow-up) writes a per-machine `WORKFLOW.local.md` from a
   template, substituting `$HOME` at install time. Keeps the loader simple but
   commits the operator to running the installer.

Either approach is outside this card's scope. Defer to a follow-up ticket when the
single-developer assumption breaks.

## Why this is advisory

- Explicitly accepted in the plan's Risks & Dependencies table.
- The PR body documents the manual edit needed for other developers.
- Single-developer scope is real today.

No action required for PRO-24 to merge.
