#!/usr/bin/env bash
# Fetch a corpus of GitLab MR review threads for pr-review-intelligence.
#
# GitLab counterpart to fetch-github-corpus.sh. The phases differ because the
# GitLab API is weaker in two ways:
#   - the MR list carries no discussion count, so the census can only prefilter
#     on user_notes_count (which includes system notes and so over-selects);
#   - there is no review object, so change-request rounds must be derived.
#
# Usage:
#   fetch-gitlab-corpus.sh PROJECT [TARGET] [SCAN_CAP] [OUTDIR] [HOST]
#
#   PROJECT   numeric id, or URL-encoded path (group%2Fsub%2Fproject)
#   TARGET    MRs with review discussion to collect  (default 30)
#   SCAN_CAP  merged MRs to scan before giving up    (default 150)
#   OUTDIR    corpus directory                       (default tmp/pr-review-intelligence)
#   HOST      GitLab hostname                        (default gitlab.com)
#
# HOST must be passed for a self-hosted instance. `glab` falls back to
# gitlab.com whenever a hostname is neither given nor inferable from the current
# directory's git remote, so an unqualified run silently mines the PUBLIC
# project of the same path. Resolve it with resolve-target.sh and pass it.
#
# Writes OUTDIR/raw/mr-N.json, each combining the MR, its discussions and commits
# so the distiller sees one self-contained record.
#
# NOTE: written from the documented GitLab REST shape. Verify resolution
# semantics on first run against a real project.

set -euo pipefail

PROJECT="${1:?usage: fetch-gitlab-corpus.sh PROJECT [TARGET] [SCAN_CAP] [OUTDIR] [HOST]}"
TARGET="${2:-30}"
SCAN_CAP="${3:-150}"
OUTDIR="${4:-tmp/pr-review-intelligence}"
HOST="${5:-gitlab.com}"

command -v glab >/dev/null || { echo "error: glab not found on PATH" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq not found on PATH" >&2; exit 2; }
glab auth status --hostname "$HOST" >/dev/null 2>&1 || {
  echo "error: glab is not authenticated to ${HOST}." >&2
  echo "       Run: glab auth login --hostname ${HOST}" >&2
  exit 2
}

mkdir -p "$OUTDIR/raw"

# --- Phase 1: census -------------------------------------------------------
echo "==> census: listing merged MRs in ${PROJECT} on ${HOST}" >&2

glab api --hostname "$HOST" --paginate \
  "projects/${PROJECT}/merge_requests?state=merged&order_by=updated_at&per_page=100" \
  | jq -s --argjson cap "$SCAN_CAP" 'add | .[0:$cap]' >"$OUTDIR/mr-list.json"

SCANNED="$(jq 'length' "$OUTDIR/mr-list.json")"
if [ "$SCANNED" -eq 0 ]; then
  echo "error: no merged MRs found in ${PROJECT}" >&2
  exit 1
fi

# user_notes_count includes system notes, so it over-selects. It is only used to
# skip MRs that definitely have nothing (count 0); real filtering happens after
# discussions are fetched and system notes are dropped.
CANDIDATES="$(jq -r '[.[] | select(.user_notes_count > 0) | .iid] | .[]' "$OUTDIR/mr-list.json")"

echo "==> census: ${SCANNED} scanned, $(echo "$CANDIDATES" | grep -c . || true) candidates" >&2

# --- Phase 2: detail -------------------------------------------------------
selected=0
selected_iids=()

for iid in $CANDIDATES; do
  [ "$selected" -ge "$TARGET" ] && break
  out="$OUTDIR/raw/mr-${iid}.json"

  if [ -s "$out" ]; then
    selected=$((selected + 1))
    selected_iids+=("$iid")
    echo "    mr-${iid} cached" >&2
    continue
  fi

  discussions="$(glab api --hostname "$HOST" --paginate \
    "projects/${PROJECT}/merge_requests/${iid}/discussions?per_page=100" | jq -s 'add')"

  # Keep only real review threads: multi-note discussions anchored to a diff,
  # with system notes ("approved this merge request", "changed the description")
  # dropped. System notes are shaped like human feedback and will flood the
  # corpus with fake signal if kept.
  real="$(jq '[ .[]
                | select(.individual_note == false)
                | select(.notes[0].type == "DiffNote")
                | .notes |= map(select(.system == false))
                | select((.notes | length) > 0) ]' <<<"$discussions")"

  if [ "$(jq 'length' <<<"$real")" -eq 0 ]; then
    continue
  fi

  mr="$(jq --argjson iid "$iid" '.[] | select(.iid == $iid)' "$OUTDIR/mr-list.json")"
  commits="$(glab api --hostname "$HOST" "projects/${PROJECT}/merge_requests/${iid}/commits" || echo '[]')"

  jq -n --argjson mr "$mr" --argjson discussions "$real" --argjson commits "$commits" \
    '{mr: $mr, discussions: $discussions, commits: $commits}' >"$out"

  selected=$((selected + 1))
  selected_iids+=("$iid")
  echo "    mr-${iid} ($(jq 'length' <<<"$real") threads)" >&2
done

if [ "$selected" -eq 0 ]; then
  echo "error: no merged MRs with diff-anchored review threads found." >&2
  echo "       This project may route review outside MR discussions." >&2
  exit 1
fi

YIELD="$(awk -v s="$selected" -v n="$SCANNED" 'BEGIN{printf "%.1f", (s/n)*100}')"

jq -n --argjson scanned "$SCANNED" --argjson selected "$selected" \
      --arg yield "$YIELD" --arg project "$PROJECT" \
      --argjson iids "$(printf '%s\n' "${selected_iids[@]}" | jq -s .)" \
  --arg host "$HOST" \
  '{project: $project, host: $host, scanned: $scanned, selected: $selected,
    yield_pct: ($yield | tonumber), selected_mrs: $iids}' \
  | tee "$OUTDIR/census.json"

echo "==> corpus ready: ${OUTDIR}/raw/ (${selected} MRs, yield ${YIELD}%)" >&2
