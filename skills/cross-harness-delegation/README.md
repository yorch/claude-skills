# cross-harness-delegation

Delegates work to a **different** AI coding agent harness — `codex`, `gemini`,
`pi`, `opencode`, `crush`, or `aider` — and treats whatever comes back as a claim
to be verified rather than a result to be trusted.

Two modes. `review` runs read-only in the live working tree, so the delegate sees
your uncommitted work and can give a genuine second opinion from a different
model family. `build` runs write-enabled inside a throwaway git worktree, so the
result arrives as an inspectable diff on its own branch and never touches your
tree until you say so.

## When to use

- Get a second opinion from a different model family — the value is the disagreement
- Offload bulk or long-running work to preserve Claude quota
- Run several harnesses in parallel across separate quota pools
- Reach a capability only another harness has (e.g. `codex --output-schema`)
- Compare how different models solve the same task, side by side

Not a replacement for in-process subagents. Use a subagent unless a *different
model or provider* is specifically the point — delegation buys model diversity
and pays for it in verification burden.

## What it produces

- `.delegates/runs/<task-id>/` — the exact brief sent, `meta.json`, raw
  stdout/stderr, `result.txt` (the delegate's claim), and `diff.patch` (the evidence)
- `.delegates/worktrees/<task-id>/` — build-mode worktree on branch `delegate/<task-id>`
- A verified diff presented for your decision. Nothing is merged automatically,
  and cleanup never deletes a delegate's branch.

## Files

- `SKILL.md` — operating principles, the two modes, and the 7-step workflow
- `references/harnesses.md` — verified per-harness flags, read-only enforcement
  tiers, and the gotchas that only surface when you actually run them
- `references/prompt-contract.md` — how to brief an agent that has zero
  conversational context
- `scripts/delegate.sh` — `list` / `run` / `collect` / `clean`; owns the worktree
  lifecycle and the harness invocation table

## The core idea

Exit code `0` means the *process* finished, not that the *work* is done. An
in-process subagent shares Claude's tool layer, so when it reports an edit the
harness genuinely performed that edit. An external harness shares only a
filesystem and an exit status — its self-report and the ground truth are produced
by entirely separate mechanisms, with nothing forcing them to agree.

Every design choice follows from that gap: the diff is the deliverable, the
summary is testimony, and verification is not optional.

## Quick start

```bash
# the script runs against YOUR repo, so invoke it by its plugin path
DELEGATE="$CLAUDE_PLUGIN_ROOT/skills/cross-harness-delegation/scripts/delegate.sh"

# what's installed, and which modes each supports
"$DELEGATE" list

# second opinion, read-only, in place
"$DELEGATE" run --harness codex --mode review --prompt-file prompt.md

# isolated build, then inspect
"$DELEGATE" run --harness codex --mode build \
    --prompt-file prompt.md --task-id refactor-auth
"$DELEGATE" collect refactor-auth   # commits the work onto delegate/refactor-auth
"$DELEGATE" clean   refactor-auth   # removes worktree, keeps branch
```

`collect` before `clean` is required, not stylistic: delegates are told not to
commit, so `collect` is what moves their output onto the branch. `clean` refuses
on a dirty worktree rather than silently discarding it.
