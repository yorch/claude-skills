# code-changes-review

Performs a thorough, professional code review of the **uncommitted changes** in
the current git working copy (both staged and unstaged). It reads the diff in
context — including unchanged files that interact with the modified code — and
reports actionable findings across correctness, security, best practices,
DRY/reusability, code smells, performance, and testing. Language- and
framework-agnostic.

## When to use

- Review my changes / code review / check my code
- Review a diff before committing (pre-commit review)
- PR review or a general quality check

## What it produces

- A structured review of the working-copy diff, with findings grouped by
  quality dimension and tied to specific files and lines — no source edits.

## Files

- `SKILL.md` — full review workflow
- `CHECKLIST.md` — the per-dimension review checklist the skill applies
