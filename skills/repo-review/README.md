# repo-review

Reviews an **entire repository** with six specialist subagents running in
parallel — product value, architecture, security, documentation accuracy,
testing and reliability, and evolution strategy — then synthesizes their findings
into a single graded `REPO_REVIEW.md`, walks you through the open decisions one
question at a time, and applies the fixes you approve on a dedicated branch.

## When to use

- Review or audit a whole codebase, not a diff
- Repo health check, technical debt assessment, "is this production ready"
- "What should we fix first" — the report is prioritized and sequenced
- Onboarding to an unfamiliar repo and needing a graded picture of it
- Producing a 90-day action plan that mixes fixes with value-building work

For **uncommitted changes**, use `code-changes-review`. For **React/Next.js
depth**, use `react-app-review`. This skill is for the repository as a whole.

## What it produces

- `REPO_REVIEW.md` — executive summary, A–F scorecard per dimension,
  cross-cutting themes, consolidated P0/P1 findings with remediation steps,
  a fixability-bucketed remediation plan, and a 90-day action plan
- A `review/remediation-<date>` branch with one commit per fixed finding
- A Remediation Log appended to the report: finding ID, action taken, commit
  hash, and verification result

## The six phases

| Phase | What happens | Writes? |
|---|---|---|
| 0 — Recon | Repo Brief, choose where to run, one frozen install | deps only |
| 1 — Parallel review | Six subagents review independently | build/test byproducts |
| 2 — Synthesis | Handle any prior report, build `REPO_REVIEW.md` + Question Queue | report only |
| 2.5 — Questions | One question at a time, never batched | no |
| 3 — Remediation | `review-remediator`, strictly sequential, on a branch | yes |
| 4 — Closeout | Remediation Log + next-steps summary | report only |

Phases 0–2 change no tracked source file. Be precise about how that is enforced,
because it differs per agent: `prod-value-reviewer`, `arch-quality-reviewer`, and
`evolution-strategist` have `tools: Read, Grep, Glob` and genuinely *cannot*
write. The other three also have `Bash`, which can write anything — their
read-only behavior is enforced by prose, not by the tool layer.

So Phases 0–1 may touch **untracked** build and test byproducts (`node_modules/`,
`coverage/`, scratch databases) if the suite is run. No *tracked* file changes
before Phase 3.

Snapshot files are the trap here: `__snapshots__/*.snap` is tracked, and test
runners write new entries by default. Phase 1 therefore runs the suite in
non-writing mode (`CI=true`, `--ci`), and reports it unrunnable rather than
letting it dirty a committed file.

## Where it runs, and re-reviewing

**In your repo by default.** A throwaway worktree is offered only when it would
genuinely help (dirty tree plus a suite that will run), and never on repos with
submodules. The caveat is stated when offered: a worktree contains only *tracked*
files, so no `.env`, no `node_modules`, and no local config — which makes the
test suite fail for reasons that have nothing to do with the repo's health. Take
the worktree and every suite-dependent `TEST-*` finding is downgraded to
`[suspected]`.

If you want `HEAD`-only *scope* rather than isolation, that is just `git stash`
first — a different axis, and no worktree needed.

**Re-reviews use the prior report.** An existing `REPO_REVIEW.md` is validated as
genuinely this skill's output, then you choose: **update** (re-verify each prior
finding and report fixed / still open / regressed / no longer applicable),
**fresh** (archive the old, review clean), or **replace**. The Phase 1 reviewers
are never shown the prior report under any option — handing an agent last month's
findings makes it confirm them rather than look with fresh eyes.

## Files

- `SKILL.md` — shared vocabulary, the phase workflow, and the orchestrator's rules
- `references/harness-portability.md` — running this outside Claude Code: what was
  verified on which harness, the tool-vocabulary mapping, and the silent-empty-review
  hazard that makes build-time validation mandatory

## Related agents

All in the plugin root's `agents/`, dispatched via `subagent_type: <name>`:

`prod-value-reviewer` · `arch-quality-reviewer` · `security-reviewer` ·
`docs-accuracy-reviewer` · `test-reliability-reviewer` · `evolution-strategist` ·
`review-remediator`

## Note on remediation concurrency

Remediators run **strictly one at a time**. Disjoint file sets are not enough to
make them safe: each commits to the same branch and index, so concurrent runs
collide on `.git/index.lock` or merge each other's staged work into a single
commit that no longer matches its recorded finding. Parallelism, if ever needed,
requires a `git worktree` per remediator — isolation at the branch level, not the
file level.
