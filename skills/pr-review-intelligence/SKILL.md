---
name: pr-review-intelligence
description: >
  Mine a repository's recent pull/merge request review history to learn what its
  reviewers actually ask for, then generate review guidelines, project pattern
  docs, a do-not-flag suppression list, and a feedback-loop report that help AI
  agents and humans review future changes the way this team reviews. Analyzes
  human review threads, the review-to-fix loop, and declined feedback. Use when:
  analyze past PRs, learn from PR feedback, generate review guidelines, mine code
  review comments, what do reviewers ask for, team review conventions, PR review
  patterns, improve AI code review, reduce review noise, codify tribal knowledge,
  review retrospective. Works with GitHub (gh) and GitLab (glab); reads review
  history only, never modifies source code.
---

# PR Review Intelligence

Turn a repository's own review history into review guidance. The output is a set of
documents in `docs/code-review/` that tell a future reviewer — agent or human — what
this specific team cares about, backed by citations to the PRs where each point
was actually raised.

The goal is **codified tribal knowledge**, not generic best practices. If a rule in
the output would be true of any repository, it does not belong there.

Throughout this document **PR** means pull request (GitHub) or merge request
(GitLab); the generated documents use whichever term matches the target forge.

## Operating principles

- **Read-only on the target repo's source.** The only files written are under
  `docs/code-review/` and the disposable `tmp/pr-review-intelligence/` scratch
  directory. Never edit source, `AGENTS.md`, `CLAUDE.md`, or CI config.
- **Every rule cites ≥2 PRs from distinct threads.** One occurrence is an
  anecdote. This gate is the defense against emitting invented advice that reads
  like mined insight — enforce it mechanically at aggregation, not by intending to
  be careful.
- **The team's revealed judgment outranks the reviewer's stated one.** A point
  raised nine times and acted on once is not a rule; it goes to `do-not-flag.md`.
- **Declined feedback is a first-class output.** Suppressing what this team does not
  want raised is as valuable as listing what it does. Roughly a quarter of automated
  review comments get rejected as out-of-scope or wrong, and that noise is what
  trains teams to ignore review output.
- **Prefer tooling over rules.** Any finding a linter could catch is reported as a
  suggested lint rule, not as something for a reviewer to nag about.
- **Bound your claims.** Report the sample size and the yield. If most merged
  PRs carried no review discussion, say so — that repo routes review elsewhere,
  and the findings are correspondingly thin.
- **Never fabricate a code example.** Anti-pattern and corrected code must come from
  real diffs in the corpus.

## Inputs

Honor anything the user supplies; otherwise use defaults:

- `repo` — `owner/name` (GitHub) or project id/path (GitLab). Default: the current
  repository, resolved from `git remote get-url origin`.
- `forge` — `github` or `gitlab`. Default: inferred from the remote host.
- `count` — PRs **with review discussion** to analyze. Default `30`.
- `scan_cap` — merged PRs to scan while looking for those. Default `150`.
- `output_dir` — default `docs/code-review/`.
- `since` — optional ISO date; restricts the sample window.

`count` is the knob that matters. Below ~15, most real patterns fail the
two-citation gate and the output thins out to platitudes. Above ~50 the returns
flatten while cost keeps climbing.

## Output structure

```text
docs/code-review/
├── review-guidelines.md          # ranked rules, grouped by path glob
├── do-not-flag.md                # suppression list + stated reasons
├── feedback-loop-report.md       # process metrics, cost concentrations
├── AGENTS-snippet.md             # routing stub for the user to paste
├── patterns/
│   └── <area>.md                 # Wrong/Correct pairs per area
└── evidence/
    └── observations.jsonl        # raw per-thread rows, for diffing re-runs
```

## Workflow

### Step 1 — Resolve the target and check tooling

```bash
git remote get-url origin
```

Derive `owner/name` and the forge from the host. Confirm the CLI is present and
authenticated (`gh auth status` or `glab auth status`). If authentication fails,
stop and tell the user — every later step depends on it.

Confirm `jq` is available; the distill step requires it.

Ensure `tmp/` is gitignored in the target repo. If it is not, say so and let the
user decide; do not edit their `.gitignore` unprompted.

### Step 2 — Fetch the corpus

```bash
bash {skill_dir}/scripts/fetch-github-corpus.sh OWNER/NAME 30 150 tmp/pr-review-intelligence
```

or, for GitLab:

```bash
bash {skill_dir}/scripts/fetch-gitlab-corpus.sh PROJECT_ID 30 150 tmp/pr-review-intelligence
```

The script runs a counts-only census first and only fetches full detail for PRs
that actually carry review threads. This matters: on an active repository only
around 10–15% of recently merged PRs have any review discussion at all, so
fetching detail for the whole window is mostly waste.

Record the reported **yield**. It goes in every generated document's provenance
header, and a yield below 10% triggers the thin-corpus warning.

If the script reports zero selected PRs, stop. The repository either routes
review outside PR threads or is too young to mine. Say which, and suggest the
user widen `scan_cap` or point at a different repository.

### Step 3 — Distill

```bash
bash {skill_dir}/scripts/distill-corpus.sh tmp/pr-review-intelligence github   # or: gitlab
```

Pass the forge that produced the corpus. The wrong one fails loudly per file
(`warn: failed to distill`) rather than emitting garbage, but it wastes a fetch.

Raw payloads reach ~200 KB per PR because `diffHunk` spans the entire hunk;
distilled records are ~5 KB and share one schema across both forges. Do not skip
this step and hand raw payloads to subagents — a single large PR can exhaust an
agent's context.

Note any PRs reported as `truncated_prs`. Counts derived from them are partial
and must be flagged in the report rather than presented as complete.

### Step 4 — Batch and fan out

Split the distilled files into batches of **5 PRs**, writing one batch manifest
per batch:

```text
tmp/pr-review-intelligence/batches/batch-01.txt   # 5 absolute paths, one per line
```

Dispatch one `pr-feedback-analyst` subagent per batch, **all in a single message**
so they run concurrently. Each invocation gets:

- `batch_file` — absolute path to its manifest
- `output_path` — `tmp/pr-review-intelligence/observations/batch-NN.jsonl`
- `skill_dir` — absolute path to this skill
- `repo_root` — absolute path to the target checkout
- `repo_slug` — `owner/name`

Each agent returns the path it wrote. Six batches covers the default 30 PRs.

### Step 5 — Aggregate and score

Concatenate the batch outputs:

```bash
cat tmp/pr-review-intelligence/observations/batch-*.jsonl \
  > tmp/pr-review-intelligence/observations.jsonl

python3 {skill_dir}/scripts/validate-observations.py \
  tmp/pr-review-intelligence/observations.jsonl
```

The validator enforces the analyst output contract and prints frequency, adherence,
and routing per exact-match cluster. It exits non-zero on contract violations —
an invented category or a dropped field would otherwise corrupt aggregation
silently. Fix or discard violating rows before continuing.

Treat its cluster table as the **floor**, not the answer: it matches patterns
exactly, so it under-counts frequency wherever two agents phrased the same pattern
differently. Semantic clustering below can only merge rows and raise frequency,
never lower it. If the validator warns that nothing cleared the evidence gate even
before merging, the corpus is likely too small — consider a larger `count` before
spending effort on synthesis.

Read the combined file and cluster observations by their `pattern` field. Clustering
is semantic, not string equality — "prefer the shared date helper over raw format()"
and "don't call format() directly for display" are one pattern.

For each cluster compute, per `references/TAXONOMY.md`:

- **frequency** — distinct PRs, not threads. Two threads in one PR count once.
- **adherence** — `addressed / (addressed + declined)`, ignoring `discussion` and `open`.
- **score** — `frequency × adherence × severity_weight`.

Then apply the gates, in order:

1. Drop clusters with fewer than 2 distinct PRs → the single-occurrence appendix.
2. Route `adherence < 0.5` → `do-not-flag.md`.
3. Route `bot_initiated` clusters → `do-not-flag.md` only, never to guidelines.
4. Route `mechanically_checkable` and `style`/`process` → suggested tooling in
   `feedback-loop-report.md`.
5. Everything else → `review-guidelines.md`, grouped by `area_glob`.

An area with a recoverable Wrong/Correct code pair also gets a `patterns/<area>.md`.

### Step 6 — Write the documents

Follow `references/TEMPLATES.md` exactly. Write the provenance header first — the
sample size and yield are what let a reader calibrate how much to trust the rest.

Before writing each rule, check it against the quality bar in
`references/TAXONOMY.md`: it must be checkable by a reviewer that sees a diff and
can read the repo. Rewrite anything that needs runtime behavior or product context,
or drop it.

Copy the aggregated observations to `docs/code-review/evidence/observations.jsonl`
so the next run can diff against it.

### Step 7 — Report

Tell the user, concisely:

- corpus size and yield, with the thin-corpus caveat if it applies
- how many rules survived the evidence gate, and how many observations were dropped
- the top three rules by score
- how many findings were routed to tooling rather than review
- what the analysis could not see
- the exact snippet to paste from `AGENTS-snippet.md`, and where

## Quality gates

Verify before reporting completion:

| Check | How |
| --- | --- |
| Observations satisfy the contract | `validate-observations.py` exits 0 |
| Every rule cites ≥2 distinct PRs | Count citations per rule block |
| Every citation link resolves to a real PR | Spot-check 3 against the corpus |
| No fabricated code examples | Every block traces to a diff in `raw/` |
| Every do-not-flag entry has a "Still flag when" boundary | Grep the file |
| Provenance header present in all generated files | Grep for "Generated by" |
| No source files modified | `git status` shows only `docs/code-review/` |

## Re-running

The corpus directory is a cache: `fetch-github-corpus.sh` skips PRs already on
disk, so a re-run with a larger `count` only fetches the new ones.

Re-run when review practice shifts — after a team change, an architecture migration,
or the adoption of a new review bot. Diff the new `evidence/observations.jsonl`
against the committed one to see what changed. A rule that has stopped appearing in
recent PRs is a rule the team may have retired.

## Forge differences

Generated documents use the target forge's vocabulary throughout — "pull request"
for GitHub, "merge request" for GitLab. Do not emit "PR/MR" into user-facing output.

The GitLab extraction path is built from the documented REST shape and verified
against a fixture, but has not been run against a live instance. Two derived fields
are weaker there and must be labelled as approximations wherever they appear in the
report: change-request rounds (GitLab has no review object) and the outdated flag
(inferred from a null `position.new_line`). See `references/EXTRACTION.md` § GitLab
caveats.
