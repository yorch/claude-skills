#!/usr/bin/env bash
# Fetch a corpus of GitHub PR review threads for pr-review-intelligence.
#
# Two phases:
#   1. Census  - counts-only search over merged PRs, filtered to those that
#                actually carry review threads. Cheap; keeps the run affordable.
#   2. Detail  - full thread payload for each selected PR, written to disk so
#                subagents read files instead of flooding orchestrator context.
#
# Usage:
#   fetch-github-corpus.sh OWNER/REPO [TARGET] [SCAN_CAP] [OUTDIR]
#
#   TARGET    PRs with review discussion to collect   (default 30)
#   SCAN_CAP  merged PRs to scan before giving up     (default 150)
#   OUTDIR    corpus directory                        (default tmp/pr-review-intelligence)
#
# Writes:
#   OUTDIR/census.json      sample frame + yield stats
#   OUTDIR/raw/pr-N.json    one detail payload per selected PR

set -euo pipefail

REPO="${1:?usage: fetch-github-corpus.sh OWNER/REPO [TARGET] [SCAN_CAP] [OUTDIR]}"
TARGET="${2:-30}"
SCAN_CAP="${3:-150}"
OUTDIR="${4:-tmp/pr-review-intelligence}"

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
if [ "$OWNER" = "$NAME" ]; then
  echo "error: REPO must be OWNER/NAME, got '$REPO'" >&2
  exit 2
fi

command -v gh >/dev/null || { echo "error: gh not found on PATH" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq not found on PATH" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated" >&2; exit 2; }

mkdir -p "$OUTDIR/raw"
QUERYDIR="$(mktemp -d)"
trap 'rm -rf "$QUERYDIR"' EXIT

cat >"$QUERYDIR/census.graphql" <<'GRAPHQL'
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
GRAPHQL

cat >"$QUERYDIR/detail.graphql" <<'GRAPHQL'
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
GRAPHQL

# --- Phase 1: census -------------------------------------------------------
# sort:updated-desc, NOT sort:comments-desc. Sorting by comment volume selects
# for mega-PRs and contentious refactors, which misrepresent routine review.
SEARCH_Q="repo:${REPO} is:pr is:merged sort:updated-desc"
CENSUS_RAW="$QUERYDIR/census-nodes.json"
: >"$CENSUS_RAW"

after=""
scanned=0
echo "==> census: scanning up to ${SCAN_CAP} merged PRs in ${REPO}" >&2

while [ "$scanned" -lt "$SCAN_CAP" ]; do
  if [ -z "$after" ]; then
    page="$(gh api graphql -F query=@"$QUERYDIR/census.graphql" -F q="$SEARCH_Q")"
  else
    page="$(gh api graphql -F query=@"$QUERYDIR/census.graphql" -F q="$SEARCH_Q" -F after="$after")"
  fi

  count="$(jq '.data.search.nodes | length' <<<"$page")"
  [ "$count" -eq 0 ] && break

  jq -c '.data.search.nodes[]' <<<"$page" >>"$CENSUS_RAW"
  scanned=$((scanned + count))

  with_threads="$(jq -s '[.[] | select(.reviewThreads.totalCount > 0)] | length' "$CENSUS_RAW")"
  echo "    scanned=${scanned} with_threads=${with_threads}" >&2
  [ "$with_threads" -ge "$TARGET" ] && break

  has_next="$(jq -r '.data.search.pageInfo.hasNextPage' <<<"$page")"
  [ "$has_next" != "true" ] && break
  after="$(jq -r '.data.search.pageInfo.endCursor' <<<"$page")"
done

# Trim to exactly SCAN_CAP so the reported yield matches the stated scan window.
jq -s --argjson cap "$SCAN_CAP" --argjson target "$TARGET" '
  (.[0:$cap]) as $frame
  | ($frame | map(select(.reviewThreads.totalCount > 0))) as $withThreads
  | {
      scanned: ($frame | length),
      with_threads: ($withThreads | length),
      selected: ($withThreads[0:$target] | length),
      yield: (if ($frame | length) > 0
              then (($withThreads | length) / ($frame | length) * 1000 | round / 10)
              else 0 end),
      selected_prs: ($withThreads[0:$target] | map(.number)),
      frame: $frame
    }' "$CENSUS_RAW" >"$OUTDIR/census.json"

YIELD="$(jq -r '.yield' "$OUTDIR/census.json")"
SCANNED="$(jq -r '.scanned' "$OUTDIR/census.json")"
SELECTED="$(jq -r '.selected' "$OUTDIR/census.json")"

echo "==> census done: ${SELECTED} selected from ${SCANNED} scanned (yield ${YIELD}%)" >&2

if [ "$SELECTED" -eq 0 ]; then
  echo "error: no merged PRs with review threads found in the scan window." >&2
  echo "       This repo may route review outside PR threads, or may be too young." >&2
  exit 1
fi

# --- Phase 2: detail -------------------------------------------------------
echo "==> detail: fetching ${SELECTED} PR payloads" >&2
truncated=0

while read -r num; do
  out="$OUTDIR/raw/pr-${num}.json"
  if [ -s "$out" ]; then
    echo "    pr-${num} cached" >&2
    continue
  fi
  gh api graphql -F query=@"$QUERYDIR/detail.graphql" \
    -F owner="$OWNER" -F name="$NAME" -F number="$num" >"$out"

  # Detect silent pagination truncation: totalCount vs returned nodes.
  total="$(jq -r '.data.repository.pullRequest.reviewThreads.totalCount' "$out")"
  got="$(jq -r '.data.repository.pullRequest.reviewThreads.nodes | length' "$out")"
  if [ "$total" != "$got" ]; then
    echo "    warn: pr-${num} truncated (${got}/${total} threads)" >&2
    truncated=$((truncated + 1))
  fi
done < <(jq -r '.selected_prs[]' "$OUTDIR/census.json")

echo "==> corpus ready: ${OUTDIR}/raw/ (${SELECTED} PRs, ${truncated} truncated)" >&2

jq -n --argjson scanned "$SCANNED" --argjson selected "$SELECTED" \
      --argjson truncated "$truncated" --arg yield "$YIELD" --arg repo "$REPO" \
  '{repo: $repo, scanned: $scanned, selected: $selected,
    truncated: $truncated, yield_pct: ($yield | tonumber)}'
