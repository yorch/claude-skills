#!/usr/bin/env bash
# Split a distilled corpus into batch manifests for the analyst fan-out.
#
# Usage:
#   make-batches.sh [OUTDIR] [BATCH_SIZE]
#
#   OUTDIR      corpus directory  (default tmp/pr-review-intelligence)
#   BATCH_SIZE  PRs per batch     (default 5)
#
# Writes OUTDIR/batches/batch-NN.txt, one absolute path per line, and prints the
# manifest list plus the fan-out plan as JSON.
#
# This is mechanical work, so it does not belong in the orchestrator's context —
# the same reason the distill step is jq rather than a model.
#
# On BATCH_SIZE: each analyst re-reads the agent prompt and CLASSIFICATION.md
# (~12 KB) regardless of batch size, so larger batches amortize that fixed cost
# over more PRs — at the price of less parallelism and a bigger per-agent context.
# 5 is a reasonable default; raising it above ~15 starts to crowd a 200K-context
# model if you have also pinned the analyst to a small tier.

set -euo pipefail

OUTDIR="${1:-tmp/pr-review-intelligence}"
BATCH_SIZE="${2:-5}"

command -v jq >/dev/null || { echo "error: jq not found on PATH" >&2; exit 2; }

case "$BATCH_SIZE" in
  ''|*[!0-9]*) echo "error: BATCH_SIZE must be a positive integer, got '$BATCH_SIZE'" >&2; exit 2 ;;
esac
[ "$BATCH_SIZE" -ge 1 ] || { echo "error: BATCH_SIZE must be >= 1" >&2; exit 2; }

[ -d "$OUTDIR/distilled" ] || {
  echo "error: $OUTDIR/distilled not found - run the distill step first" >&2
  exit 2
}

# Resolve to absolute paths: the analyst agents receive manifests, not a cwd.
ABS_OUT="$(cd "$OUTDIR" && pwd)"

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$ABS_OUT/distilled" -maxdepth 1 -name '*.json' | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "error: no distilled records in $OUTDIR/distilled" >&2
  exit 1
fi

rm -rf "$ABS_OUT/batches"
mkdir -p "$ABS_OUT/batches" "$ABS_OUT/observations"

n=0
batch=0
manifest=""
for f in "${files[@]}"; do
  if [ $((n % BATCH_SIZE)) -eq 0 ]; then
    batch=$((batch + 1))
    manifest="$(printf '%s/batches/batch-%02d.txt' "$ABS_OUT" "$batch")"
    : >"$manifest"
  fi
  printf '%s\n' "$f" >>"$manifest"
  n=$((n + 1))
done

echo "==> ${n} PRs into ${batch} batches of up to ${BATCH_SIZE}" >&2

jq -n \
  --argjson prs "$n" \
  --argjson batches "$batch" \
  --argjson size "$BATCH_SIZE" \
  --arg dir "$ABS_OUT" \
  --argjson manifests "$(find "$ABS_OUT/batches" -name 'batch-*.txt' | sort | jq -R . | jq -s .)" \
  '{prs: $prs, batches: $batches, batch_size: $size,
    manifests: $manifests,
    observations_dir: ($dir + "/observations")}'
