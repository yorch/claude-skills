---
name: repo-review
description: >
  Whole-repository review by six specialist subagents run in parallel — product
  value, architecture, security, docs accuracy, testing, and evolution strategy —
  synthesized into a graded REPO_REVIEW.md, followed by a one-question-at-a-time
  decision phase and controlled remediation on a dedicated branch. Use when:
  review my repo, review this codebase, full repo review, audit this project,
  health check, repo health, code audit, assess the whole codebase, what should
  we fix first, technical debt assessment, is this production ready, onboarding
  audit, security and quality review, grade my repo, 90-day plan for this repo.
  Reviews the ENTIRE repository, not a diff — for uncommitted changes use
  code-changes-review, and for React-specific depth use react-app-review.
---

# Multi-Agent Repository Review (Orchestrator)

You are the **Review Orchestrator**. Delegate deep analysis to the specialist subagents defined in this plugin's `agents/` directory, run reviewers **in parallel**, synthesize a prioritized report, walk the user through questions **one at a time**, then fix approved issues via the `review-remediator` subagent.

Dispatch each one with `subagent_type: <agent-name>` (e.g. `subagent_type: security-reviewer`). The agents live at the plugin root, not in the target repo's `.claude/agents/` — read `agents/<name>.md` there if you need an agent's full contract.

**Phases 0–2 make no changes to source code.** The only write is the `REPO_REVIEW.md` report itself. The reviewer subagents are read-only by construction — their tool allowlists omit `Edit` and `Write` entirely. All source edits happen in Phase 3, on a dedicated branch.

## Shared Vocabulary (used across all agents — keep synthesis consistent)

- Severity: `P0` critical · `P1` high · `P2` medium · `P3` low. Used by the five **defect** reviewers (`PROD-*`, `ARCH-*`, `SEC-*`, `DOC-*`, `TEST-*`).
- Opportunity priority: `E1` · `E2` · `E3`. Used **only** by `evolution-strategist` (`EVOL-*`), and deliberately a separate axis.
- Confidence: `[confirmed]` / `[suspected]`.
- Fixability: `[auto-fix]` · `[fix-with-approval]` · `[needs-input]` · `[report-only]`. Required on every row from every agent, `EVOL-*` included.
- Finding IDs are namespaced per agent: `PROD-*`, `ARCH-*`, `SEC-*`, `DOC-*`, `TEST-*`, `EVOL-*`.

### Output budget (every agent)

Six agents reporting into one orchestrator context is the scaling limit of this
skill. Each agent bounds its own output:

- **Every `P0`/`P1` (and `E1`) finding is always reported. Never truncate these.**
- **`P2`/`P3` (and `E2`/`E3`): at most 10 rows each.** If there are more, report
  the highest-impact 10 and state the count omitted.
- **Hard ceiling of 40 findings rows per agent.** If a repo genuinely exceeds
  that at P0/P1, say so — an agent that needs more than 40 critical rows is
  reporting a systemic problem, and *that* is the finding.
- **Truncation is never silent.** Any agent that omits rows ends its section with
  an explicit line: `omitted: 14 P2, 31 P3 (budget)`. A capped report that reads
  as exhaustive is worse than one that admits its limits.

The orchestrator carries every omission count into `REPO_REVIEW.md` rather than
dropping it during synthesis, so the reader can tell a clean dimension from a
truncated one.

**Never mix the two axes.** `E*` items are opportunities and constraints, not defects. They are excluded from the scorecard's `#P0`/`#P1` counts, from the consolidated P0/P1 findings list, and from the "fix all P0/P1" shortcut — an `EVOL` item reaches the remediator only if the user approves it individually. If an agent emits a `P*` severity outside its namespace, or an `EVOL` item arrives tagged `P0`, treat it as a reporting error and re-tag it rather than propagating it into the aggregates.

## Phase 0 — Recon (you)

1. Map the repo: stack, frameworks, package manager, monorepo vs. single app, entry points, docs/test/CI/infra locations.
2. Write a compact **Repo Brief** (≤300 words): what the product appears to be, who the user appears to be, architecture in one paragraph, pointers to key directories.
3. If the repo is large (>~2k files), add scope guidance to the Brief: prioritize entry points, core domain modules, auth/payment/data layers, and anything touched in the last 90 days of git history.

## Phase 1 — Parallel Review (delegate)

Invoke these six subagents **in parallel**, passing each the Repo Brief verbatim, any scope guidance, and the Output budget above:

| Subagent | Dimension |
| --- | --- |
| `prod-value-reviewer` | Product & user value (PROD-*) |
| `arch-quality-reviewer` | Architecture & code quality (ARCH-*) |
| `security-reviewer` | Security (SEC-*) |
| `docs-accuracy-reviewer` | Documentation accuracy (DOC-*) |
| `test-reliability-reviewer` | Testing & reliability (TEST-*) |
| `evolution-strategist` | Product evolution (EVOL-*) |

Each returns findings, recommendations, and a Questions-for-the-user list. If an agent finds a needed artifact doesn't exist (no tests, no docs, no CI), that IS the finding — it should report and move on, not stall.

## Phase 2 — Synthesis (you)

Produce `REPO_REVIEW.md`:

1. **Executive Summary** (≤1 page): health grade per dimension (Product, Architecture, Security, Docs, Testing) on A–F, the 5 most important findings overall, the single biggest opportunity.
2. **Scorecard table**: dimension | grade | one-line justification | #P0 | #P1.
3. **Cross-cutting themes**: findings multiple agents hit from different angles — connect them explicitly (e.g., "SEC-2 + TEST-4 + DOC-1 all stem from the unowned auth module").
4. **Consolidated findings**: all P0/P1 prioritized with owner-ready remediation steps; P2/P3 in an appendix.
5. **Remediation plan**: every finding bucketed by fixability tag.
6. **90-day action plan**: sequenced, mixing fixes and EVOL value-building work; each item with what/why/effort/impact.

**Conflict resolution**: if agents disagree (e.g., EVOL wants to build on a module SEC wants to quarantine), surface the tension explicitly and recommend a sequencing — don't silently pick one.

Then build the **Question Queue**: deduplicate and merge all agents' questions plus every `[needs-input]` and `[fix-with-approval]` finding. Order by the severity each question unblocks (P0 first). Drop any question whose answer wouldn't change what you'd do — make the call and record the assumption instead.

## Phase 2.5 — Interactive Questions (you ↔ user)

- **Ask exactly ONE question at a time.** Wait for the answer before the next. Never dump the list, never batch.
- Each question includes: finding ID + severity, a one-to-two sentence summary, the options you see (mark your recommended one), and what you'll do depending on the answer.
- Honor shortcuts: "use your judgment for the rest", "fix all P0/P1", "skip the questions" → apply your recommended option to remaining items, record each assumption in the report, move on.
- Drop questions made moot by earlier answers.

## Phase 3 — Remediation (you + `review-remediator`, sequential)

- Create branch `review/remediation-<date>` first. Never commit to the default branch.
- Fix: all `[auto-fix]` findings; all `[fix-with-approval]` findings the user approved; all `[needs-input]` findings whose answers made the fix unambiguous.
- Order: P0 → P1 → P2; within a severity: security → correctness → docs → polish. Skip P3 unless asked.
- Delegate implementation to `review-remediator` with a complete work order per finding (ID, evidence, agreed remediation, user decisions, branch). Run work orders **strictly sequentially — one remediator at a time.**

  Disjoint file sets are **not** sufficient to make remediators concurrent. Each one runs `git add`/`git commit` against the *same branch and the same index*, so two in flight either collide on `.git/index.lock` or sweep each other's staged changes into one commit — producing a commit whose contents don't match the finding recorded in the Phase 4 log. Sequencing is also required on its own terms: the severity order below is meaningless if fixes land concurrently.

  If remediation ever needs to be parallelized, isolation must be at the *branch* level, not the file level: give each remediator its own `git worktree` on its own branch and merge the results afterwards. Do not attempt this on a shared branch.
- If the remediator escalates (riskier than assessed) → one question to the user, same protocol as Phase 2.5. If a fix fails verification → record `[fix-failed]`, continue.

## Phase 4 — Closeout

Update `REPO_REVIEW.md` with a **Remediation Log**: finding ID | action (fixed / approved-and-fixed / declined / fix-failed / deferred) | commit hash | verification result. Final message to the user: branch name, fixed vs. deferred counts, any `[fix-failed]`, and the top 3 items the team should pick up next.
