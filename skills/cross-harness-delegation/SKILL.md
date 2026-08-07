---
name: cross-harness-delegation
description: >
  Delegate work to a different AI coding agent harness — codex, gemini, pi,
  opencode, crush, or aider — and verify what comes back. Two modes: `review`
  runs read-only in the live tree for a second opinion from a different model
  family; `build` runs write-enabled inside a throwaway git worktree so the
  result arrives as an inspectable diff on its own branch. Use when: delegate to
  another agent, second opinion from another model, ask Codex, ask Gemini, run
  this with opencode, cross-check with a different AI, offload work to save
  Claude quota, run several agents in parallel, compare how different models
  solve the same task, agent handoff, external agent, other CLI agent.
  Never merges anything without showing you the diff first.
---

# Cross-harness delegation

Hand a task to a *different* agent harness and treat its output as a claim to be
verified, not a result to be trusted.

## When this is the right tool

Delegate when a **different model or provider is the point**:

- A second opinion where the value is in the disagreement
- Offloading bulk work to preserve Claude quota
- Running several harnesses in parallel across separate quota pools
- A capability only another harness has (e.g. enforced output schemas)

**Otherwise use an in-process subagent.** A subagent shares Claude's tool layer,
so its reports are backed by the same machinery that performed the work. A
delegate shares only a filesystem and an exit code. Delegation buys model
diversity and pays for it in verification burden — do not pay that price for
work a subagent handles fine.

## Operating principles

- **Exit code 0 means the process finished, not that the work is done.** This is
  the crux of the whole skill. Never report success from an exit status.
- **The diff is evidence; the summary is a claim.** Read `diff.patch`. The
  delegate's own account of what it did is unverified testimony.
- **Never relay a delegate's claim as fact.** Check cited `path:line` references
  against the real file before passing a finding to the user.
- **Read-only means enforced by the tool, not requested in the prompt.**
  `crush` and `aider` have no read-only mode and are never used for review.
- **Confirm before spending someone else's quota.** Build and fan-out runs are
  billed to another provider that this session cannot see or account for.
- **Never merge without showing the diff.** Integration is the user's decision.

## Modes

| | `review` | `build` |
|---|---|---|
| Runs in | current working directory | throwaway git worktree |
| Writes | blocked by the harness's own sandbox | allowed, bounded by the worktree |
| Sees uncommitted work | **yes** | no — starts from a ref |
| Produces | a text/JSON verdict | a branch plus a diff |
| Dispatch | automatic | **confirm first** |

Review runs in place because a worktree is created *at a commit* and therefore
cannot contain the uncommitted work a review is usually about. Containment for
review comes from the sandbox flag instead.

## Workflow

### 1. Classify

Review or build? If genuinely ambiguous, ask — the modes have different blast
radii and different billing profiles.

### 2. Route

```bash
skills/cross-harness-delegation/scripts/delegate.sh list
```

Filter to installed × mode-eligible, then choose on capability
(see `references/harnesses.md`):

- Need an **enforced output shape** → `codex` (`--output-schema` is the only
  mechanism that guarantees rather than requests a format)
- Need the **strongest read-only guarantee** → `codex` or `gemini`
- Need **fine-grained tool control** → `pi` (`-t` allowlist / `-xt` denylist)
- Need **model diversity above all** → pick a different provider family than the
  one that produced the code under review

State the choice and the reason. If nothing is eligible, say so — never silently
substitute a harness the user did not expect.

### 3. Gate

- **A single review** dispatches without asking: read-only, cheap, reversible.
- **Any build, or any fan-out**, prints the plan and waits:

```text
Plan:
  codex  → build → worktree .delegates/worktrees/<id> → branch delegate/<id>
  gemini → build → worktree .delegates/worktrees/<id2> → branch delegate/<id2>
  2 delegates, write mode, billed to OpenAI + Google
Proceed?
```

### 4. Brief

Write `prompt.md` following `references/prompt-contract.md`. All six sections.
The delegate has **no conversational context** — under-briefing is the most
common cause of a useless result.

### 5. Dispatch

```bash
# review — in place, read-only
./scripts/delegate.sh run --harness codex --mode review --prompt-file prompt.md

# build — worktree isolated
./scripts/delegate.sh run --harness codex --mode build \
    --prompt-file prompt.md --task-id refactor-auth
```

For parallel fan-out, run each in the background with a distinct `--task-id`.
Each gets its own worktree and branch, so there is no shared state and no
coordination protocol is needed.

### 6. Verify — mandatory

```bash
./scripts/delegate.sh collect <task-id>
```

Then, without exception:

- **Read `diff.patch`.** Not `result.txt`. The summary is a claim.
- **Run the tests yourself** in the worktree. Never accept "tests pass".
- **Scope check.** Flag any file in the diff outside the expected set.
- **Commit-discipline check.** Verify the actual commit state matches what the
  brief demanded.
- **Citation check (review mode).** Open each cited `path:line`. Findings that
  cannot be verified against a real line are discarded, not relayed.

A delegate reporting success with an empty diff has done nothing. This is a real
observed failure, not a hypothetical — see the `aider` self-update case in
`references/harnesses.md`.

### 7. Integrate or discard

Present the verified diff and let the user decide. Then:

```bash
./scripts/delegate.sh clean <task-id>   # removes worktree, KEEPS the branch
git branch -D delegate/<task-id>        # separate, explicit discard
```

Cleanup never destroys delegate output. Discarding is always a distinct step.

## Artifacts

Everything lands in `.delegates/` at the repo root (add to `.gitignore`):

```text
.delegates/
├── worktrees/<task-id>/       # build mode; branch delegate/<task-id>
└── runs/<task-id>/
    ├── prompt.md              # exact brief sent (auditable)
    ├── meta.json              # harness, mode, model, base_sha, exit_code
    ├── stdout.log / stderr.log
    ├── result.txt             # the delegate's claim
    └── diff.patch             # the evidence
```

## Exit codes

- `0` — harness ran to completion. **Not a success signal.**
- `1` — harness exited non-zero (auth failure, crash). Check `stderr.log`.
- `2` — precondition failed (unknown or uninstalled harness, ineligible mode,
  duplicate task-id, not a git repo).

## Failure modes

- **Hangs with no output** → almost always stdin. `delegate.sh` redirects
  `</dev/null` for this reason; never remove it.
- **Installed but not authenticated** → exit 1 with the reason in `stderr.log`.
  Distinguish from task failure before retrying.
- **Exit 0, empty diff** → the harness did nothing. Read `references/harnesses.md`.
- **Diff full of unrelated files** → the harness wrote its own config, history,
  or gitignore entries. Tighten the flags rather than accepting the noise.
- **Delegate committed when told not to** → check every time; defaults vary.

## References

- `references/harnesses.md` — verified per-harness flags, enforcement tiers, and
  the gotchas found by running them
- `references/prompt-contract.md` — how to brief an agent with no context
