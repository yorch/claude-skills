# Harness registry

Every flag below was read from the installed binary's `--help` on 2026-08-06.
**`pi`, `opencode`, `codex`, `crush`, and `aider` were additionally confirmed by
an actual headless run.** The `gemini` rows are verified as *parsed correctly*
only — a full run is blocked by an upstream `IneligibleTierError` on this
machine, so treat them as unproven until auth is restored.

Rows are re-verifiable in seconds — prefer re-running `delegate.sh list` and a
probe over trusting this file if a harness has been upgraded.

Routing is decided on *verified capability*, never on quality claims like
"harness X is better at refactoring". Capability claims can be falsified with a
local command; quality claims rot invisibly.

## Read-only enforcement tiers

The tier decides whether a harness may be used for `review` mode, which runs
**in the live working tree**. Getting this wrong means a "reviewer" edits your code.

| Tier | Meaning | Harnesses |
|---|---|---|
| `enforced` | The harness itself refuses writes via a sandbox or approval policy | `codex`, `gemini`, `pi` |
| `configured` | Restriction comes from agent configuration — real, but weaker and user-overridable | `opencode` |
| `none` | No read-only mode exists. **Ineligible for review.** | `crush`, `aider` |

`opencode` is deliberately `configured` rather than `enforced`: `opencode agent list`
shows its `plan` agent carrying `{"permission": "*", "action": "allow"}` — the
same entry as `build`. Its read-only behavior comes from the agent's tool
configuration, which is not visible in the permission dump and can be
overridden by user config. Treat it as weaker than `codex -s read-only`.

`crush` and `aider` are excluded from review because restricting them to reading
would be a *request in the prompt*, not a guarantee from the tool.

## Verified invocations

| Harness | review | build |
|---|---|---|
| `codex` | `codex exec -s read-only -o <result>` | `codex exec -s workspace-write -o <result>` |
| `gemini` | `gemini --skip-trust --approval-mode plan -p <prompt>` | `gemini --skip-trust --approval-mode yolo -p <prompt>` |
| `pi` | `pi -p -t read,grep,find,ls` | `pi -p` |
| `opencode` | `opencode run --agent plan` | `opencode run --auto` |
| `crush` | — ineligible — | `crush run --quiet` |
| `aider` | — ineligible — | `aider --yes-always --no-auto-commits --no-check-update --no-gitignore --message-file <f>` |

Prompt delivery differs: `aider` takes `--message-file`, `gemini` takes `-p`,
everything else takes a trailing positional argument. Working directory is set
by `cd`, not by per-harness cwd flags, so only one mechanism has to be correct.

## Gotchas found by running these, not by reading docs

These are the bugs that headless delegation actually hits. Each cost a failed
run to discover.

### stdin must be `/dev/null` — universal

`codex exec` detects a non-TTY stdin and **blocks forever** printing
`Reading additional input from stdin...`, even when the prompt was already
supplied on argv. Its help explains why: *"If stdin is piped and a prompt is
also provided, stdin is appended as a `<stdin>` block."* Any non-interactive
parent process gives it a pipe, so it waits for EOF that never comes.

`delegate.sh` redirects `</dev/null` for every harness. Never remove it. This is
the single most likely cause of a delegation that hangs with no output.

### `gemini` silently discards `--approval-mode` without `--skip-trust`

Running `gemini --approval-mode plan` in an untrusted folder prints
`Approval mode overridden to "default" because the current folder is not trusted`
and proceeds with approval prompts — which then hang or fail headlessly. The
requested mode is dropped, not honored. `--skip-trust` is required for the
approval mode to take effect at all.

### `gemini --approval-mode auto_edit` is not enough for build

`auto_edit` auto-approves **edit tools only**. Shell and other tool calls still
require approval, and with stdin closed a headless run deadlocks or aborts the
moment the delegate tries to run the build or test command — which the prompt
contract requires every build brief to specify. `yolo` is the only workable
setting for headless build; never use it for review.

**Be precise about what that costs.** A git worktree bounds *git state* — the
branch, the index, what lands in the diff. It does **not** sandbox the
filesystem. Under `yolo`, gemini can still run arbitrary commands that write
outside the worktree entirely. That is materially weaker containment than
`codex exec -s workspace-write`, which is an actual sandbox. Prefer `codex` for
build tasks when the choice is free, and treat `gemini:build` as trusted-input
only.

### `crush --yolo` does not work with `run`

`crush --help` lists `-y --yolo` under global FLAGS, but `crush run` rejects it
in **every** position with `Unknown flag: --yolo`. It applies to interactive mode
only. This turns out not to matter: **`crush run` already auto-approves** in
non-interactive mode — verified by having it write a file with no approval flag
at all. Passing `--yolo` breaks the invocation; omit it.

### `aider` self-updates instead of working, and exits 0

Default `aider` checks for a new version, installs it, prints
`Re-run aider to use new version`, does no work, and **exits 0**. A caller
trusting the exit code sees success and an empty diff. `--no-check-update` is
mandatory.

`aider` also, by default: auto-commits (`--auto-commits` defaults to **True**),
writes `.aider.chat.history.md` into the working tree, and appends its own
entries to `.gitignore`. All three land in the diff and obscure the real change.
Hence `--no-auto-commits --no-gitignore` plus redirected history files.

### Exit code 0 does not mean the task succeeded

This is not harness-specific — it is the structural property of the whole
approach. A POSIX exit status reports that the *process* finished, not that the
*work* is done. The `aider` self-update case above is the cleanest illustration:
exit 0, zero files changed, cheerful output. Always read `diff.patch`.

## Environment notes for this machine

- `gemini` currently fails authentication with
  `IneligibleTierError: This client is no longer supported for Gemini Code
  Assist for individuals`. Its flags are verified as *parsed correctly*, but a
  full run is unverified until auth is restored. `delegate.sh` reports this as
  exit 1 with the error in `stderr.log`, correctly distinguished from a
  precondition failure (exit 2).
- `pi`, `opencode`, `codex`, `crush`, `aider` were all confirmed working
  end-to-end.

## Adding a harness

1. Confirm a genuine headless mode (`--help`) and run it once by hand.
2. Determine the read-only tier honestly. If you cannot point at a flag the tool
   itself enforces, the tier is `none` and it is build-only.
3. Add it to `HARNESSES` and to both `case` statements in `delegate.sh`.
4. Probe it with a trivial prompt before trusting it. Verify it does not hang
   (stdin), does not self-update, and does not write stray files into the tree.
