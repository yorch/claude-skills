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

**Phases 0–2 make no changes to source code.** All source edits happen in Phase 3, on a dedicated branch.

Be precise about how strongly that is enforced, because it differs per agent:

- **`prod-value-reviewer`, `arch-quality-reviewer`, `evolution-strategist`** have `tools: Read, Grep, Glob`. They *cannot* write — the constraint is enforced by the tool layer.
- **`security-reviewer`, `docs-accuracy-reviewer`, `test-reliability-reviewer`** additionally have `Bash`, which can write anything. Their read-only behavior is enforced by prose, not by the tool layer, and is therefore weaker.

Phase 1 can therefore touch **untracked build and test byproducts** — `node_modules/`, `coverage/`, `.pytest_cache/`, scratch test databases — if the test suite is run. Do not promise a user an untouched working tree; promise that no tracked file changes before Phase 3.

**Run the suite in non-writing mode.** Snapshot files (`__snapshots__/*.snap`, `.ambr`) are *tracked* artifacts, and Jest/Vitest write new ones by default when a test has no stored snapshot — which would dirty a committed file during a phase that promises not to. Set `CI=true`, and pass the runner's non-writing flag: `--ci` (Jest/Vitest), `--snapshot-update=none` where supported, `pytest -p no:cacheprovider`. If the suite cannot be run without writing tracked files, report it as unrunnable rather than running it.

## Shared Vocabulary (used across all agents — keep synthesis consistent)

- Severity: `P0` critical · `P1` high · `P2` medium · `P3` low. Used by the five **defect** reviewers (`PROD-*`, `ARCH-*`, `SEC-*`, `DOC-*`, `TEST-*`).
- Opportunity priority: `E1` · `E2` · `E3`. Used **only** by `evolution-strategist` (`EVOL-*`), and deliberately a separate axis.
- Confidence: `[confirmed]` / `[suspected]`.
- Fixability: `[auto-fix]` · `[fix-with-approval]` · `[needs-input]` · `[report-only]`. Required on every row from every agent, `EVOL-*` included.
- Finding IDs are namespaced per agent: `PROD-*`, `ARCH-*`, `SEC-*`, `DOC-*`, `TEST-*`, `EVOL-*`.

### Output budget (every agent)

Six agents reporting into one orchestrator context is the scaling limit of this
skill. Each agent bounds its own output:

- **`P2`/`P3` (and `E2`/`E3`): at most 10 rows each.** If there are more, report
  the highest-impact 10 and state the count omitted.
- **`P0`/`P1` (and `E1`) are reported in full, up to 40 rows.** Beyond 40
  criticals, list the 40 highest-impact and state the true total — a repo with
  more than 40 critical findings in one dimension has a systemic problem, and
  *that* is the headline finding, not the 41st row.
- **Truncation is never silent.** Any agent that omits rows ends its section with
  an explicit line: `omitted: 14 P2, 31 P3 (budget)`. A capped report that reads
  as exhaustive is worse than one that admits its limits.

Note the caps are per-tier and deliberately not a single total: since `P2` and
`P3` can never exceed 20 rows between them, an overall "40 rows" ceiling could
only ever bind on the critical findings you must not drop.

The orchestrator carries every omission count into `REPO_REVIEW.md` rather than
dropping it during synthesis, so the reader can tell a clean dimension from a
truncated one.

**Never mix the two axes.** `E*` items are opportunities and constraints, not defects. They are excluded from the scorecard's `#P0`/`#P1` counts, from the consolidated P0/P1 findings list, and from the "fix all P0/P1" shortcut — an `EVOL` item reaches the remediator only if the user approves it individually. If an agent emits a `P*` severity outside its namespace, or an `EVOL` item arrives tagged `P0`, treat it as a reporting error and re-tag it rather than propagating it into the aggregates.

## Phase 0 — Recon (you)

1. Map the repo: stack, frameworks, package manager, monorepo vs. single app, entry points, docs/test/CI/infra locations.
2. Write a compact **Repo Brief** (≤300 words): what the product appears to be, who the user appears to be, architecture in one paragraph, pointers to key directories.
3. If the repo is large (>~2k files), add scope guidance to the Brief: prioritize entry points, core domain modules, auth/payment/data layers, and anything touched in the last 90 days of git history.
4. **Decide where the review runs. Default: in place, in the user's repo.**

   Two independent axes, and conflating them is a design error:
   - **Isolation** — in the user's tree, or in a throwaway `git worktree`.
   - **Scope** — the working tree including uncommitted work, or `HEAD` only.

   A worktree changes *both*: it is isolated **and** it is `HEAD`-only, because a worktree is created at a commit and contains **only tracked files**. That second consequence is what makes it a poor default:

   - No `.env` or local config → the suite very likely fails → `test-reliability-reviewer` files a false P0/P1 against a suite that works fine for the user.
   - No `node_modules` → a cold install on every review.
   - **Submodules break worktree creation and removal.** Never offer a worktree if `.gitmodules` exists.
   - A worktree nested under the repo can pick up the parent's tool config (mocha, jest, tsconfig), producing findings about the wrong configuration.

   So: **offer** a worktree only when it would genuinely help — the tree is dirty *and* the suite will be run — and state the cost plainly. If the user takes it, downgrade every `TEST-*` finding that depends on running the suite to `[suspected]` and say why in the report. If the user wants `HEAD`-only *scope* without isolation, that is just `git stash` first; do not create a worktree for it.

5. **Prepare the environment ONCE, here, before any fan-out.** If the test suite needs dependencies installed, run a single frozen-lockfile install now and record in the Brief whether it succeeded.

   Use exactly one, matching the lockfile present: `npm ci` · `yarn install --immutable` · `pnpm install --frozen-lockfile` · `bun install --frozen-lockfile` · `uv sync --frozen` · `poetry sync` (Poetry ≥2; `poetry install --sync` on 1.x) · `BUNDLE_FROZEN=true bundle install`. Never a bare `npm install` / `yarn install` / `pnpm install` — those rewrite the lockfile.

   **Every command above must be per-invocation.** Use the `BUNDLE_FROZEN=true` environment variable, never `bundle config set --local frozen true`: that writes `BUNDLE_FROZEN: "true"` into `<repo>/.bundle/config`, a file that is frequently tracked, so it would both violate this phase's own no-tracked-changes promise and leave frozen mode enabled after the review ends — the user's next `bundle install` after a `Gemfile` change then hard-fails. (It is also Bundler 2.x-only syntax and a silent no-op on Bundler 1.x, which would leave the install unfrozen and rewrite the lockfile.)

   This must happen in Phase 0 because Phase 1 runs **in parallel**: `npm ci` deletes and recreates `node_modules` wholesale, so an install racing `security-reviewer`'s `npm audit` or `test-reliability-reviewer`'s own suite run produces `MODULE_NOT_FOUND` failures that an agent cannot distinguish from a real defect — and a spurious P0/P1 then flows into the scorecard and the "fix all P0/P1" shortcut. Installing once, sequentially, before dispatch removes the race entirely.

   If no frozen install is available for this repo, say so in the Brief. Reviewers must then report the suite as unrunnable rather than installing anything themselves.

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

**If this harness has no subagent capability**, run the six dimensions yourself, sequentially, in your own context — using each agent's contract from `agents/<name>.md` as your instructions for that pass. The review still works; it is slower, the dimensions are no longer independent, and one context holds everything. Label the report **single-context review** so nobody mistakes it for six independent passes. Do not silently skip dimensions.

**Treat an empty review as a misconfiguration, not a clean dimension.** If a reviewer returns no findings *and* cites no files it read, it almost certainly had no usable tools — a ported agent whose tool names do not match this harness's vocabulary is granted nothing and returns nothing, with a zero exit code. Six such sections would synthesise into a confident "no issues found" on a repo nobody actually examined. Re-run that dimension; if it comes back empty again, record it as `not reviewed (harness/tooling)` in the scorecard rather than as a grade. See `references/harness-portability.md`.

Each returns findings, recommendations, and a Questions-for-the-user list. If an agent finds a needed artifact doesn't exist (no tests, no docs, no CI), that IS the finding — it should report and move on, not stall.

## Phase 2 — Synthesis (you)

**First, handle any existing `REPO_REVIEW.md`.** Re-reviewing is a normal flow, and a prior report is *input*, not just an obstacle: it holds what this run cannot reconstruct — which findings the user declined, the answers given in Phase 2.5, and the Remediation Log tying findings to commits. Never overwrite it silently.

**Validate it first.** Confirm it is actually this skill's output: a Scorecard table, a findings table with namespaced IDs (`SEC-*`, `ARCH-*`, …), and an Executive Summary. If those are absent, it is somebody else's file that happens to share the name — **do not touch it**. Write to `REPO_REVIEW-<YYYY-MM-DD>.md` instead and say so.

If it validates, report what you found (its date, finding count, and how many its Remediation Log records as fixed) and offer:

1. **Update** — re-verify each prior finding and report a delta: `fixed` · `still open` · `regressed` · `no longer applicable`. Best for a repo being actively improved; it answers "did our fixes stick?", which a fresh review cannot.
2. **Fresh** — archive to `REPO_REVIEW-<prior-date>.md` and review clean.
3. **Replace** — discard the prior report. Only offer this when it is tracked and unmodified, since git still has it; otherwise its contents exist nowhere else.

**In every case, the Phase 1 reviewers are never shown the prior report.** Discovery must stay independent — an agent handed last month's findings tends to confirm them rather than look with fresh eyes, and a regression that reappeared somewhere new gets filed under the old location. Only the orchestrator reads it, in this phase, to compute the delta.

Carry forward the prior report's declined findings as a **Previously declined** section under any option, so a re-review never re-litigates a decision the user already made.

Then produce `REPO_REVIEW.md`:

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
- **A shortcut answers questions; it does not narrow the remediation scope.** "Fix all P0/P1" means *stop asking me and use your recommendation* — Phase 3 still fixes P0–P2 as defined below. It does not mean "and skip P2". Stated explicitly because the shortcut's wording and Phase 3's scope name different tiers, and without this rule whether a dozen P2 `[auto-fix]` commits land varies run to run — the same nondeterminism the P3 precedence rule exists to remove. If the user genuinely wants a narrower scope, they will say so; confirm rather than infer it from the shortcut's phrasing.
- Drop questions made moot by earlier answers.

## Phase 3 — Remediation (you + `review-remediator`, sequential)

- **Refuse to start Phase 3 on a dirty working tree**, excluding this skill's own deliverable:

  ```bash
  git status --porcelain -- . ':!REPO_REVIEW.md' ':!REPO_REVIEW-*.md'
  ```

  If that is non-empty, stop and ask the user to commit or stash first (offer to stash). This is a hard precondition, not politeness: the remediator's failure-recovery is `git restore --staged --worktree`, which restores from `HEAD`. If the user had uncommitted edits in a file the remediator touches, that recovery silently destroys them — and working-tree content that was never committed has no reflog to recover from. A clean tree is what makes `HEAD` equal the pre-fix state.

  **The exclusions are required, not cosmetic.** A bare `git status --porcelain` lists untracked files as `?? REPO_REVIEW.md`, and Phase 2 always writes that file — so an unexcluded check is non-empty on *every* run, first or repeat, and Phase 3 could never start at all.
- Create branch `review/remediation-<date>` first. Never commit to the default branch. If that branch already exists — a same-day re-review is a normal flow — append `-2`, `-3`, … rather than failing or reusing it.
- **Commit `REPO_REVIEW.md` onto that branch as its first commit**, before dispatching any remediator. Phase 2 writes the report into the working tree while still on the default branch, and no remediator will ever stage it — `review-remediator` is forbidden from touching anything outside its work order. Left uncommitted, the skill's primary deliverable is an untracked file: absent from the branch anyone pulls, and destroyed by any `git clean -fd`.
- Fix, at **P0–P2**: all `[auto-fix]` findings; all `[fix-with-approval]` findings the user approved; all `[needs-input]` findings whose answers made the fix unambiguous.
- **Plus any individually-approved `E*` item.** The severity gate is about defects; an `EVOL` item the user explicitly approved in Phase 2.5 is remediated on its own authority and never carries a P severity by construction. Without this carve-out the shared vocabulary's promise that "an `EVOL` item reaches the remediator only if the user approves it individually" would be unreachable, and the orchestrator would be pushed into re-tagging it with a P severity — the exact reporting error that section forbids.
- Order: P0 → P1 → P2; within a severity: security → correctness → docs → polish.
- **P3 is skipped unless the user asks — including P3 `[auto-fix]` findings.** Severity gates before fixability; the two rules are not independent. Without this precedence a review that surfaces 30 P3 `[auto-fix]` doc typos is ambiguous: "fix all `[auto-fix]`" and "skip P3" give opposite answers, and behavior varies run to run. If the user does ask for P3, batch **all** P3 auto-fixes into a **single** commit rather than one per finding — thirty one-line commits is not what "minimal diffs" means.
- Delegate implementation to `review-remediator` with a complete work order per finding (ID, evidence, agreed remediation, user decisions, branch). Run work orders **strictly sequentially — one remediator at a time.**

  Disjoint file sets are **not** sufficient to make remediators concurrent. Each one runs `git add`/`git commit` against the *same branch and the same index*, so two in flight either collide on `.git/index.lock` or sweep each other's staged changes into one commit — producing a commit whose contents don't match the finding recorded in the Phase 4 log. Sequencing is also required on its own terms: the P0 -> P1 -> P2 severity order above is meaningless if fixes land concurrently.

  If remediation ever needs to be parallelized, isolation must be at the *branch* level, not the file level: give each remediator its own `git worktree` on its own branch and merge the results afterwards. Do not attempt this on a shared branch.
- If the remediator escalates (riskier than assessed) → one question to the user, same protocol as Phase 2.5. If a fix fails verification → record `[fix-failed]`, continue.

## Phase 4 — Closeout

Update `REPO_REVIEW.md` with a **Remediation Log**: finding ID | action (fixed / approved-and-fixed / declined / fix-failed / deferred) | commit hash | verification result. Carry forward any `omitted: … (budget)` counts from Phase 1 so a truncated dimension is never mistaken for a clean one.

**Commit the updated report** as the final commit on the remediation branch, so the branch you hand over actually contains it.

Final message to the user: branch name, fixed vs. deferred counts, any `[fix-failed]`, and the top 3 items the team should pick up next.
