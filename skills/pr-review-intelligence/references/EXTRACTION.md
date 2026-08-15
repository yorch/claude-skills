# Extraction Reference

How to pull review-thread corpora out of GitHub and GitLab, and the field traps that
silently corrupt the analysis if you get them wrong.

All GitHub queries in this document were verified against a live public repository.
The GitLab queries are built from the documented REST shape and are **not** verified
against a live instance — see [GitLab caveats](#gitlab-caveats).

## Contents

- [Concepts and forge mapping](#concepts-and-forge-mapping)
- [GitHub extraction](#github-extraction)
- [GitLab extraction](#gitlab-extraction)
- [Field traps](#field-traps)
- [On-disk corpus layout](#on-disk-corpus-layout)

## Concepts and forge mapping

The analysis needs six things per review thread. Each forge names them differently:

| Concept | GitHub (GraphQL) | GitLab (REST) |
| --- | --- | --- |
| Change request | `PullRequest` (`number`) | merge request (`iid`) |
| Review thread | `reviewThreads.nodes[]` | `discussions[]` where `individual_note == false` |
| Anchored to code | thread always is | note `type == "DiffNote"` |
| Resolved | `isResolved` + `resolvedBy` | note `resolved` + `resolved_by` |
| Code changed under it | `isOutdated` | no field — infer from `position.new_line == null` |
| File / line | `path`, `line`, `startLine` | `position.new_path`, `position.new_line` |
| Code context | `diffHunk` on the comment | not returned — fetch the diff separately |
| Suggested edit | ` ```suggestion ` fence in body | structured `suggestions[]` array |
| Round count | `reviews[].state == CHANGES_REQUESTED` | no review object — derive from commits |
| Bot vs human | `author.__typename` (`Bot` / `User`) | `author.username` heuristic + `system` flag |

Two asymmetries drive most of the per-forge branching:

- **GitLab has no first-class review object.** GitHub gives you `CHANGES_REQUESTED`
  as an explicit round marker. On GitLab you must derive rounds from the commit
  timeline versus discussion timestamps.
- **GitLab has no `isOutdated`.** GitHub tells you directly that the code under a
  comment changed. On GitLab the proxy is a `DiffNote` whose `position.new_line`
  has gone `null`, which means the anchored line no longer exists in the new diff.

## GitHub extraction

Requires `gh` authenticated with repo read scope. Verify first:

```bash
gh auth status
```

### Phase 1 — census (cheap)

Never fetch full thread bodies for the whole candidate window. Run a counts-only
census, filter to PRs that actually have review discussion, and only then fetch
detail. On an active repo, **most recently merged PRs have zero review threads**
(auto-merges, dependency bumps, rubber-stamp approvals), so the census is what keeps
the run affordable.

Write the query to a file — inlining multi-line GraphQL into a shell argument is
where quoting bugs come from:

```graphql
# census.graphql
query($q:String!,$after:String){
  search(query:$q, type:ISSUE, first:50, after:$after){
    pageInfo{ hasNextPage endCursor }
    nodes{
      ... on PullRequest{
        number title mergedAt changedFiles additions deletions
        author{ login }
        commits{ totalCount }
        reviews(first:1){ totalCount }
        reviewThreads(first:1){ totalCount }
      }
    }
  }
}
```

`reviews` and `reviewThreads` both expose `totalCount`, so `first:1` costs nothing
while still returning the count.

```bash
gh api graphql -F query=@census.graphql \
  -F q='repo:OWNER/NAME is:pr is:merged sort:updated-desc' \
  --jq '.data.search.nodes[] | select(.reviewThreads.totalCount > 0) | .number'
```

Page with `-F after=<endCursor>` until you have enough PRs or hit the scan cap.

**Do not** sample with `sort:comments-desc`. It looks appealing but it selects for
outliers — 100+ commit mega-PRs and contentious refactors — which are the least
representative of routine review. Use `sort:updated-desc` and filter.

Record the **yield** (PRs with threads / PRs scanned). A yield under ~10% means the
repo routes most review outside PR threads, and the report must say so rather than
present thin findings as a complete picture.

### Phase 2 — detail (per selected PR)

```graphql
# detail.graphql
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      number title url mergedAt changedFiles additions deletions
      author{ login __typename }
      commits(first:100){ totalCount nodes{ commit{ oid committedDate messageHeadline } } }
      reviews(first:50){ nodes{ author{ login __typename } state submittedAt bodyText } }
      reviewThreads(first:50){
        totalCount
        nodes{
          isResolved isOutdated path line startLine
          resolvedBy{ login }
          comments(first:20){
            nodes{
              author{ login __typename }
              bodyText createdAt diffHunk originalLine
              reactionGroups{ content users{ totalCount } }
            }
          }
        }
      }
    }
  }
}
```

Run once per selected PR and write the raw JSON to disk. Do not let raw payloads
into the orchestrator's context — subagents read the files.

```bash
gh api graphql -F query=@detail.graphql \
  -F owner=OWNER -F name=NAME -F number=1234 \
  > tmp/pr-review-intelligence/raw/pr-1234.json
```

Use `bodyText` rather than `body`. `bodyText` is the rendered plaintext, which
strips markdown noise. The exception is when you need to detect a ` ```suggestion `
block — that requires the raw `body`, so request both if suggestion detection
matters for the repo.

## GitLab extraction

Requires `glab` authenticated against the instance:

```bash
glab auth status
```

Project id may be numeric or the URL-encoded path (`group%2Fsubgroup%2Fproject`).

### Phase 1 — census

GitLab's MR list does not return a discussion count, so the census is weaker than
GitHub's: list merged MRs, then probe discussions per MR. Use `user_notes_count` on
the MR list as a cheap prefilter — it counts all notes including system ones, so it
over-selects, but an MR with `user_notes_count == 0` definitely has no threads.

```bash
glab api --paginate \
  "projects/:id/merge_requests?state=merged&order_by=updated_at&per_page=100"
```

### Phase 2 — detail

```bash
glab api --paginate "projects/:id/merge_requests/<iid>/discussions?per_page=100"
glab api "projects/:id/merge_requests/<iid>/commits"
glab api "projects/:id/merge_requests/<iid>/approvals"
```

Filter the discussions to real review threads:

```bash
glab api --paginate "projects/:id/merge_requests/<iid>/discussions?per_page=100" \
  | jq '[ .[]
          | select(.individual_note == false)
          | select(.notes[0].type == "DiffNote")
          | { resolved: .notes[0].resolved,
              path: .notes[0].position.new_path,
              line: .notes[0].position.new_line,
              notes: [ .notes[] | select(.system == false)
                       | {author: .author.username, body, created_at} ] } ]'
```

### GitLab caveats

- **`system: true` notes must be filtered out.** GitLab emits notes for
  `"approved this merge request"`, `"changed the description"`, `"marked as draft"`,
  and dozens of other lifecycle events. They are indistinguishable from human
  feedback by shape alone and will flood the corpus with fake signal if kept.
- **No `isOutdated`.** Use `position.new_line == null` on a `DiffNote` as the proxy
  for "the anchored code changed."
- **No review states.** Approvals are a separate endpoint and carry no
  `CHANGES_REQUESTED` equivalent, so round counting must come from comparing commit
  timestamps against discussion timestamps.
- **Bot detection is heuristic.** There is no `__typename` equivalent. Match against
  the known bot usernames for the instance, and treat any account whose notes are
  all `system: true` as non-human.
- This path is written from the documented API shape and has **not** been executed
  against a live GitLab instance. Treat field names as correct but verify resolution
  semantics on first run against a real project.

## Field traps

These are the mistakes that produce plausible-looking but wrong analysis.

### `diffHunk` reads backwards

`diffHunk` spans from the hunk header **down to the commented line**. The code the
reviewer is talking about is the **last** lines of the string, not the first.

Truncating from the front (`diffHunk[0:500]`) returns the top of the file and
discards the anchor entirely — the single most likely way to get context wrong here.
Observed hunks reach ~19 KB / 600+ lines on large new files, so passing them whole
is also a token bomb.

Take the tail:

```bash
jq -r '.diffHunk | split("\n") | .[-20:] | join("\n")'
```

`originalLine` corresponds to the final line of `diffHunk`, which is a useful
consistency check.

### `isResolved` under-counts fixes

A thread can end with the author writing *"all the commands now run with git hooks
disabled"* and still carry `isResolved: false` — many teams simply never click
resolve. Scoring on `isResolved` alone systematically undercounts addressed feedback
and will make a healthy repo look like it ignores its reviewers.

Classify a thread as **addressed** when any of these hold:

1. `isResolved == true`, **or**
2. `isOutdated == true` — the code under the comment changed after it was written, **or**
3. the last comment is by the PR author and confirms a change
   (*"done"*, *"fixed"*, *"moved to…"*, *"good catch, updated"*).

Classify as **declined** when the thread ends with the author deferring or pushing
back and neither 1 nor 2 holds (*"out of scope"*, *"we can follow up"*,
*"working as intended"*). Declined threads are the primary source of
`do-not-flag.md` — see `SCORING.md`.

### Bot logins are inconsistent across fields

The same GitHub App appears as `vercel` in `author.login` but `vercel[bot]` in
`resolvedBy.login`. Never match bots by login string. Use
`author.__typename == "Bot"`.

Bot comments are not junk — they are **inverted signal**. A bot suggestion the team
repeatedly declined is direct evidence of what that team considers noise. Mine bot
threads into `do-not-flag.md`, never into `review-guidelines.md`.

### Threads without file anchors

`line` is `null` on outdated threads. Fall back to `originalLine`, and keep `path`,
which stays populated. A thread with neither is a general PR comment, not a review
thread — exclude it.

### Pagination silently truncates

`reviewThreads(first:50)` and `comments(first:20)` cover the overwhelming majority of
PRs, but a mega-PR will exceed them. Compare `reviewThreads.totalCount` against the
returned node count; if they differ, either page or record the PR as partially
sampled. Never report a count derived from a silently truncated fetch.

## On-disk corpus layout

Raw payloads stay out of the target repo's version control and out of the
orchestrator's context:

```text
tmp/pr-review-intelligence/
├── census.json              # counts-only sample frame + yield stats
├── raw/
│   ├── pr-1234.json         # one detail payload per selected PR
│   └── pr-1235.json
└── batches/
    └── batch-01.txt         # file paths handed to each analyst subagent
```

Add `tmp/` to the target repo's `.gitignore` if it is not already ignored. The
durable artifact is the output directory; `tmp/` is disposable scratch that makes
re-runs cheap.
