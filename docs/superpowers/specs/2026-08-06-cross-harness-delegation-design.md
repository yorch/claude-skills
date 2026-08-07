# cross-harness-delegation — Design

**Date:** 2026-08-06
**Status:** Approved

## Problem

Claude Code can dispatch in-process subagents, but it cannot currently hand work
to a *different* agent harness — `codex`, `gemini`, `pi`, `opencode`, `crush`,
`aider`. Four distinct motivations argue for that capability:

1. **Second opinion / model diversity** — a different model family reviews or
   independently solves something; the value is in the disagreement.
2. **Cost and quota offload** — push bulk or long-running work onto a cheaper or
   free-tier harness to preserve Claude quota.
3. **Parallelism across quota pools** — run several harnesses concurrently so
   throughput is not bottlenecked on one provider's rate limit.
4. **Capability gap** — route a task to the harness whose capabilities actually
   fit it (enforced structured output, very large context, fine-grained tool
   restriction).

These four share one core primitive — *invoke harness X headlessly in directory
D with prompt P and capture a result* — and differ only in the policy layer
applied on top.

## Non-goals

- Not a session multiplexer or TUI manager (that is `agent-mux` / `claude-squad`
  territory).
- Not a general MCP bridge or a long-lived agent-to-agent protocol.
- Not a replacement for in-process subagents. Delegation is for when a
  *different model or provider* is the point; otherwise use a subagent.

## Verified harness contracts

All flags below were read from the installed binaries' `--help` output on
2026-08-06, not from documentation. Every row is re-verifiable in one second.

| Harness | Headless invocation | Structured output | Read-only enforcement | Session resume |
|---|---|---|---|---|
| `pi` | `pi -p "<prompt>"` | `--mode json` | `-t <allowlist>` / `-xt <denylist>` / `--no-tools` | `-c`, `--session <id>`, `--fork` |
| `opencode` | `opencode run "<prompt>"` | `--format json` | via `--agent <name>` only | `-c`, `-s <id>`, `--fork` |
| `codex` | `codex exec "<prompt>"` | `--json`, `-o <file>`, `--output-schema <file>` | `-s read-only` | `codex exec resume --last` |
| `gemini` | `gemini -p "<prompt>"` | `-o json\|stream-json` | `--approval-mode plan` | `-r latest`, `--session-id` |
| `crush` | `crush run "<prompt>"` | none | **none** | `-s <id>`, `-C` |
| `aider` | `aider -m "<msg>"` | none | **none** | n/a (git-based) |

Three consequences drive the design:

- `codex --output-schema <FILE>` is the only mechanism that can *enforce* a JSON
  shape on a final answer. Everything else is a prompt-level request.
- `codex -s read-only` and `gemini --approval-mode plan` are genuine sandboxes.
  `crush` and `aider` have no read-only mode at all.
- `gemini -w/--worktree` creates a git worktree natively; every other harness
  needs one created for it.

## Design

### Two modes

| | `review` | `build` |
|---|---|---|
| Location | current cwd, in place | throwaway git worktree |
| Sandbox | harness read-only flag, enforced | harness write flag, bounded by worktree |
| Sees uncommitted work | yes | no (starts from a ref) |
| Deliverable | text/JSON verdict | a branch plus a diff |
| Dispatch gate | automatic | confirm first |

The two modes exist because worktree isolation protects against writes but also
isolates against *reads*. A fresh worktree is created at a commit, so it cannot
contain the uncommitted work that a review is usually about. Review therefore
runs in place with the harness's own read-only sandbox doing the containment.

### Write policy

Build-mode delegates always run in a throwaway git worktree on their own branch.
The delegate writes freely inside it; Claude reads the resulting diff and decides
what to integrate. The diff is simultaneously the blast-radius bound and the
verification artifact.

### Harness eligibility

`crush` and `aider` are **structurally ineligible for review mode**. They expose
no read-only enforcement, so restricting them to reading would be a prompt-level
request rather than a guarantee. The registry encodes this as a hard exclusion.

Routing filters the registry by *installed* × *mode-eligible*, then selects on
verified capability — never on unfalsifiable quality claims. If no harness
survives for the requested mode, the skill says so rather than silently
substituting one.

### Dispatch gate

- A single `review` delegation dispatches without asking: cheap,
  non-destructive, reversible.
- Any `build` delegation, or any fan-out to multiple harnesses, prints the plan
  (harness, mode, prompt, worktree, branch) and waits for approval.

The rationale is that delegation spends *another provider's* quota, which the
Claude session cannot see or account for. That makes dispatch an outward-facing
action rather than an internal implementation detail.

## Structure

```text
skills/cross-harness-delegation/
├── SKILL.md                     # workflow + routing judgment
├── README.md                    # per-repo convention
├── references/
│   ├── harnesses.md             # verified per-harness flag table
│   └── prompt-contract.md       # how to brief a context-less delegate
└── scripts/
    └── delegate.sh              # list / run / collect / clean
```

A single script rather than two: `list` and `run` share registry parsing, and
duplicating that across files guarantees drift.

### Artifact layout

Repo-root `.delegates/`, gitignored:

```text
.delegates/
├── worktrees/<task-id>/         # build mode only; branch delegate/<task-id>
└── runs/<task-id>/
    ├── prompt.md                # exact brief sent (auditable)
    ├── meta.json                # harness, mode, model, base ref, cmd, exit code
    ├── stdout.log / stderr.log  # raw harness output
    ├── result.txt               # final message, extracted
    └── diff.patch               # build mode only
```

Inside the repo rather than a sibling directory, so temp artifacts stay
discoverable and easy to clean. Tradeoff: a nested worktree is visible to tools
that ignore `.gitignore` (git and ripgrep honor it; some IDE indexers do not).

### Script contract

```bash
delegate.sh list
delegate.sh run --harness <h> --mode review --prompt-file <f> [--model M]
delegate.sh run --harness <h> --mode build --prompt-file <f> --task-id <slug> [--base HEAD] [--model M]
delegate.sh collect <task-id>
delegate.sh clean <task-id>
```

Exit codes, deliberately three:

- `0` — the harness ran to completion. **This does not mean the task succeeded.**
- `1` — the harness exited non-zero.
- `2` — precondition failed (not installed, ineligible for the mode, or build
  requested outside a git repository).

`clean` removes the worktree and **keeps the branch**. Nothing a delegate
produced is destroyed by cleanup; discarding is a separate explicit
`git branch -D`. Teardown uses `git worktree remove --force` and falls back to
`rm -rf` plus `git worktree prune`, because worktree removal is known to fail on
non-empty directories and on repos with submodules.

**No timeout flag.** macOS ships no `timeout(1)`. Foreground runs take their
limit from Claude's Bash tool timeout; parallel fan-out runs backgrounded with no
limit and is polled. Known limitation: a wedged background delegate needs a
manual kill.

## Workflow

1. **Classify** — review or build. Ask if ambiguous; the modes have different
   blast radii.
2. **Route** — filter by installed × eligible, select on capability, state the
   choice and the reason.
3. **Gate** — auto for a single review; confirm for build or fan-out.
4. **Brief** — write `prompt.md` per the prompt contract.
5. **Dispatch** — `delegate.sh run`.
6. **Verify** — mandatory, non-skippable.
7. **Integrate or discard** — merge, cherry-pick, or delete the branch.

### Prompt contract

The delegate has **zero conversational context**: it has not read the thread,
does not know what has been tried, and cannot ask. A brief adequate for an
in-process subagent is usually badly under-specified here. Required sections:

- **Task** — imperative, self-contained, no pronouns pointing outside the brief
- **Context** — relevant paths, what has been attempted and ruled out
- **Acceptance criteria** — verifiable (e.g. "`npm test` passes")
- **Constraints** — do not commit; do not modify lockfiles; do not touch paths
  outside the named set
- **Output format** — exactly what to emit as the final message
- **Honesty clause** — "if you cannot complete this, say so explicitly; do not
  report success you did not achieve"

### Verification rules

- **Never relay a delegate's claim as fact.** A verdict citing `foo.ts:42` is
  checked against `foo.ts:42` before it reaches the user. Delegates hallucinate
  line numbers.
- **Build mode reads `diff.patch`, not `result.txt`.** The summary is a claim;
  the diff is evidence.
- **Run the tests yourself** in the worktree. Do not accept "tests pass".
- **Scope check** — flag any file in the diff outside the expected set.
- **Commit-discipline check** — `aider` auto-commits unless given
  `--no-auto-commits`; verify actual commit state against what the brief demanded.

These rules are deliberately stronger than those applied to an in-process
subagent. A subagent shares Claude's tool layer, so when it reports an edit the
harness genuinely performed that edit. An external harness shares only a
filesystem and an exit code, so its self-report and the ground truth are produced
by separate mechanisms with nothing forcing them to agree.

### Parallel fan-out

Each delegate gets its own task-id, worktree, and branch, so there is no shared
state and no coordination protocol is needed. Dispatch is backgrounded, the plan
is confirmed up front, and results are collected and compared diff-by-diff.

## Failure modes to document

- Harness installed but not authenticated — fails fast; distinguish from task
  failure.
- Harness ignores headless flags and blocks on an interactive prompt.
- Delegate installs dependencies or rewrites a lockfile inside the worktree.
- Delegate commits when told not to, or fails to commit when told to.
- Cost surprise from an unconfirmed fan-out.

## Deliverables

- `skills/cross-harness-delegation/` (SKILL.md, README.md, 2 references, 1 script)
- A new row in the root `README.md` skills table
- A `.delegates/` entry in `.gitignore`
