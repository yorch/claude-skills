#!/usr/bin/env bash
# Normalize a raw PR/MR corpus into the forge-neutral schema the analyst agent reads.
#
# Usage:
#   distill-corpus.sh [OUTDIR] [FORGE]
#
#   OUTDIR  corpus directory   (default tmp/pr-review-intelligence)
#   FORGE   github | gitlab    (default github)
#
# Reads  OUTDIR/raw/*.json
# Writes OUTDIR/distilled/*.json  and prints a size-reduction summary.
#
# Raw payloads reach ~200 KB per PR because diffHunk spans the entire hunk.
# Distilled records are ~5 KB, which is what makes fanning out to subagents viable.

set -euo pipefail

OUTDIR="${1:-tmp/pr-review-intelligence}"
FORGE="${2:-github}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/distill-${FORGE}.jq"

command -v jq >/dev/null || { echo "error: jq not found on PATH" >&2; exit 2; }
[ -f "$FILTER" ] || { echo "error: no distiller for forge '$FORGE' at $FILTER" >&2; exit 2; }
[ -d "$OUTDIR/raw" ] || { echo "error: $OUTDIR/raw not found - run the fetch step first" >&2; exit 2; }

mkdir -p "$OUTDIR/distilled"

ok=0
failed=0
threads=0

for f in "$OUTDIR"/raw/*.json; do
  [ -e "$f" ] || { echo "error: no raw payloads in $OUTDIR/raw" >&2; exit 1; }
  name="$(basename "$f")"
  if jq -f "$FILTER" "$f" >"$OUTDIR/distilled/$name.tmp" 2>"$OUTDIR/distilled/$name.err"; then
    mv "$OUTDIR/distilled/$name.tmp" "$OUTDIR/distilled/$name"
    rm -f "$OUTDIR/distilled/$name.err"
    n="$(jq '.threads | length' "$OUTDIR/distilled/$name")"
    threads=$((threads + n))
    ok=$((ok + 1))
  else
    echo "    warn: failed to distill $name" >&2
    sed 's/^/      /' "$OUTDIR/distilled/$name.err" >&2 || true
    rm -f "$OUTDIR/distilled/$name.tmp"
    failed=$((failed + 1))
  fi
done

# Flag any PR whose threads were silently truncated by pagination, so counts in
# the final report are never derived from a partial fetch.
truncated="$(jq -s '[.[] | select(.threads_total > .threads_fetched) | .number]' \
  "$OUTDIR"/distilled/*.json)"

raw_size="$(du -sk "$OUTDIR/raw" | cut -f1)"
dist_size="$(du -sk "$OUTDIR/distilled" | cut -f1)"

echo "==> distilled ${ok} PRs (${failed} failed), ${threads} review threads" >&2
echo "==> size ${raw_size}K -> ${dist_size}K" >&2

jq -n --argjson ok "$ok" --argjson failed "$failed" --argjson threads "$threads" \
      --argjson truncated "$truncated" --arg forge "$FORGE" \
  '{forge: $forge, distilled: $ok, failed: $failed,
    total_threads: $threads, truncated_prs: $truncated}'
