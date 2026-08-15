# pr-review-intelligence

Mines a repository's recent pull/merge request review history to learn what its
reviewers actually ask for, then generates review guidance backed by citations to
the PRs where each point was raised. The output is **codified tribal knowledge** —
if a rule would be true of any repository, it does not belong in the output.

Works with GitHub and GitLab, including GitHub Enterprise and self-hosted GitLab
(`gh` / `glab`). Read-only on source; the only files
written are under the output directory and a disposable `tmp/` scratch directory.
The output directory is claimed with a provenance marker on first run, and the
skill refuses to overwrite a directory it did not create.

## When to use

- Analyze past PRs to learn team review conventions, or run a review retrospective
- Generate review guidelines for AI agents so they review the way this team reviews
- Reduce AI review noise by mining what the team has repeatedly declined
- Codify tribal knowledge that lives only in senior reviewers' heads

## What it produces

In `docs/review-intelligence/` (override with `output_dir`):

- `review-guidelines.md` — ranked rules grouped by path glob, each with what to
  detect, the team's stated reasoning, and citing PRs
- `do-not-flag.md` — feedback the team repeatedly declined, with the stated reason
  and a mandatory "still flag when" boundary
- `patterns/<area>.md` — Wrong/Correct code pairs per area, drawn from real diffs
- `feedback-loop-report.md` — process metrics: adherence by category, patterns
  driving the most review rounds, findings that should move to tooling
- `AGENTS-snippet.md` — a routing stub to paste into `AGENTS.md`, `CLAUDE.md`, or
  `.github/copilot-instructions.md`
- `evidence/observations.jsonl` — raw per-thread rows, for diffing re-runs

## How it works

1. **Census** — a counts-only search over merged PRs, filtered to those that
   actually carry review threads. On an active repo only ~10–15% do, so this is
   what keeps the run affordable.
2. **Distill** — raw payloads reach ~200 KB per PR; distilled records are ~5 KB and
   share one schema across both forges.
3. **Fan out** — batches of 5 PRs go to parallel `pr-feedback-analyst` subagents,
   each emitting one JSONL observation per review thread.
4. **Score** — clusters are ranked by `frequency × adherence × severity_weight`,
   where adherence is the share of times the team actually acted on the feedback.
5. **Gate** — a rule needs ≥2 citing PRs from distinct threads or it is dropped to
   an appendix. Low-adherence and bot-initiated clusters route to `do-not-flag.md`;
   mechanically checkable findings route to a suggested lint rule instead.

## Cost

Every stage runs on the cheapest thing that can do its job, and most stages run on
no model at all — distillation is `jq`, gating is Python, batching is shell. The
analyst subagent pins `model: sonnet` with `effort: medium`: a bounded extraction
task against a fixed schema doesn't need the top tier, but outcome classification
has one hard case (reviewer pushes back, author concedes) where a misread inverts
adherence and silently suppresses a real rule. `CLAUDE_CODE_SUBAGENT_MODEL`
overrides the pin session-wide. See SKILL.md § Model tiering.

## Files

- `SKILL.md` — operating principles, inputs, seven-step workflow, quality gates
- `references/EXTRACTION.md` — forge queries, field mapping, and the field traps
  that silently corrupt the analysis
- `references/CLASSIFICATION.md` — outcome definitions, language cues, categories.
  The analyst's only reference, kept small because it is re-read once per batch
- `references/SCORING.md` — scoring, routing, evidence gate, rule quality bar.
  Orchestrator-only; the analyst never reads it
- `references/TEMPLATES.md` — templates for the five output documents
- `scripts/` — host/forge resolution, corpus fetch and distill for both forges,
  batch manifests, an output-directory guard, an observation-contract validator
  that applies the routing gates by arithmetic, and a GitLab fixture

## Related

- Uses the `pr-feedback-analyst` subagent (in the plugin's `agents/`) during the
  parallel fan-out phase, one invocation per batch of PRs.
- Output is consumed by any reviewer that reads `AGENTS.md` — including the
  `code-changes-review` skill — via the generated routing stub. The skills stay
  decoupled; nothing is wired automatically.

## Caveats

- **GitLab is unverified against a live instance.** The path is built from the
  documented REST shape and verified against a fixture. Two fields are weaker
  there and are labelled as approximations in output: change-request rounds
  (GitLab has no review object) and the outdated flag.
- **Self-hosted instances resolve the host explicitly, and have not been run
  against a live deployment.** `gh` and `glab` both silently fall back to their
  public host when a hostname is neither passed nor inferable from the working
  directory, which would mine an unrelated public repo of the same name — so the
  host is resolved once and passed to every call, and an unauthenticated host
  fails rather than falling back. On GitHub Enterprise, a low yield may mean the
  instance's search index is incomplete rather than that the team doesn't review.
- **Findings are only as good as the corpus.** A repository that reviews in chat,
  squashes without thread history, or rubber-stamps most PRs will yield thin
  results — the report states its own yield and warns when the sample is thin.
