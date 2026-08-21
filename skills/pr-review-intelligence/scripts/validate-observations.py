#!/usr/bin/env python3
"""Validate analyst observations and preview the routing gates.

    validate-observations.py OBSERVATIONS.jsonl [--json]

Two jobs, both mechanical on purpose:

1. Enforce the pr-feedback-analyst output contract. A subagent that invents a
   category or drops a field would otherwise corrupt aggregation silently.
2. Compute frequency, adherence and routing per cluster, so the evidence gate is
   applied by arithmetic rather than by the model remembering to apply it.

Clustering here is exact-match on `pattern`. The skill's aggregation step does
the semantic clustering; this is a floor, not a replacement — it catches contract
violations and shows how much evidence actually exists before any merging.

Exit codes: 0 valid, 1 contract violations found, 2 usage error.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict

CATEGORIES = {
    "correctness", "security", "error-handling", "api-contract", "data",
    "testing", "performance", "architecture", "convention", "readability",
    "style", "docs", "process",
}
OUTCOMES = {"addressed", "declined", "discussion", "open"}
CONFIDENCE = {"high", "medium", "low"}
MECHANICAL_CATEGORIES = {"style", "process"}

REQUIRED: dict[str, type | tuple[type, ...]] = {
    "pr": int,
    "url": str,
    "path": str,
    "area_glob": str,
    "category": str,
    "outcome": str,
    "pattern": str,
    "reviewer_ask": str,
    "resolution": str,
    "bot_initiated": bool,
    "reversal": bool,
    "mechanically_checkable": bool,
    "confidence": str,
}

EVIDENCE_THRESHOLD = 2
ADHERENCE_THRESHOLD = 0.5


def validate(rows: list[tuple[int, dict]]) -> list[str]:
    errors: list[str] = []
    for lineno, o in rows:
        missing = sorted(set(REQUIRED) - set(o))
        if missing:
            errors.append(f"line {lineno}: missing fields {missing}")
        extra = sorted(set(o) - set(REQUIRED))
        if extra:
            errors.append(f"line {lineno}: unexpected fields {extra}")
        for key, typ in REQUIRED.items():
            if key in o and not isinstance(o[key], typ):
                got = type(o[key]).__name__
                errors.append(f"line {lineno}: {key} should be {typ.__name__}, got {got}")
        if o.get("category") not in CATEGORIES:
            errors.append(f"line {lineno}: bad category {o.get('category')!r}")
        if o.get("outcome") not in OUTCOMES:
            errors.append(f"line {lineno}: bad outcome {o.get('outcome')!r}")
        if o.get("confidence") not in CONFIDENCE:
            errors.append(f"line {lineno}: bad confidence {o.get('confidence')!r}")
        if len(str(o.get("pattern", ""))) > 120:
            errors.append(f"line {lineno}: pattern is {len(o['pattern'])} chars (max 120)")
        if len(str(o.get("reviewer_ask", ""))) > 240:
            errors.append(f"line {lineno}: reviewer_ask is {len(o['reviewer_ask'])} chars (max 240)")
    return errors


def route(freq: int, adherence: float | None, bot: bool, mechanical: bool) -> str:
    """Routing gates, in the order the skill specifies."""
    if freq < EVIDENCE_THRESHOLD:
        return "appendix"
    if bot:
        return "do-not-flag"
    if adherence is not None and adherence < ADHERENCE_THRESHOLD:
        return "do-not-flag"
    if mechanical:
        return "tooling"
    return "review-guidelines"


def cluster(rows: list[tuple[int, dict]]) -> list[dict]:
    acc: dict[str, dict] = defaultdict(
        lambda: {"prs": set(), "addressed": 0, "declined": 0, "bot": False, "mechanical": True}
    )
    for _, o in rows:
        c = acc[o.get("pattern", "")]
        c["prs"].add(o.get("pr"))
        c["bot"] = c["bot"] or bool(o.get("bot_initiated"))
        # A cluster is only tooling-routable if EVERY observation in it is.
        c["mechanical"] = c["mechanical"] and (
            bool(o.get("mechanically_checkable")) or o.get("category") in MECHANICAL_CATEGORIES
        )
        if o.get("outcome") == "addressed":
            c["addressed"] += 1
        elif o.get("outcome") == "declined":
            c["declined"] += 1

    out = []
    for pattern, c in acc.items():
        denom = c["addressed"] + c["declined"]
        adherence = round(c["addressed"] / denom, 2) if denom else None
        freq = len(c["prs"])
        out.append({
            "pattern": pattern,
            "frequency": freq,
            "adherence": adherence,
            "addressed": c["addressed"],
            "declined": c["declined"],
            "bot_initiated": c["bot"],
            "route": route(freq, adherence, c["bot"], c["mechanical"]),
        })
    out.sort(key=lambda r: (-r["frequency"], r["pattern"]))
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv[1:]
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2

    rows: list[tuple[int, dict]] = []
    parse_errors: list[str] = []
    try:
        with open(args[0], encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append((lineno, json.loads(line)))
                except json.JSONDecodeError as exc:
                    parse_errors.append(f"line {lineno}: invalid JSON: {exc}")
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    errors = parse_errors + validate(rows)
    clusters = cluster(rows)

    if as_json:
        json.dump({"observations": len(rows), "errors": errors, "clusters": clusters},
                  sys.stdout, indent=2)
        print()
        return 1 if errors else 0

    print(f"observations: {len(rows)}")
    if errors:
        print(f"contract violations: {len(errors)}")
        for e in errors:
            print(f"  FAIL {e}")
    else:
        print("contract: OK")

    counts: dict[str, int] = defaultdict(int)
    for c in clusters:
        counts[c["route"]] += 1

    print(f"\nclusters: {len(clusters)}  " + "  ".join(
        f"{k}={v}" for k, v in sorted(counts.items())))
    print(f"{'freq':>4}  {'adher':>5}  {'route':<18}  pattern")
    for c in clusters:
        adher = "-" if c["adherence"] is None else f"{c['adherence']:.2f}"
        print(f"{c['frequency']:>4}  {adher:>5}  {c['route']:<18}  {c['pattern'][:70]}")

    if not any(c["route"] == "review-guidelines" for c in clusters):
        print("\nwarning: no cluster cleared the evidence gate - the corpus is too "
              "small or too varied to support any rule. Widen the sample.")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
