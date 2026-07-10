# repo-wiki-generator

Generates a DeepWiki-style structured wiki for any git repository: an Overview
page, one page per detected subsystem, and detail pages for major components —
with Mermaid architecture diagrams and **commit-pinned** source citations. It
fans out per-page generation across parallel subagents and writes everything to
a configurable output directory (default `./wiki/`) inside the target repo.
Read-only on source; language- and size-agnostic.

## When to use

- Generate a wiki, document a codebase, or auto-generate docs (deepwiki-style)
- Produce an architecture overview, codebase walkthrough, or onboarding docs
- Generate an `ARCHITECTURE.md` or build a code map for an open-source repo

## What it produces

- A `wiki/` directory: `README.md` (overview + index), `_SIDEBAR.md` nav,
  `1-repository-structure.md`, one `N-<subsystem>.md` per subsystem (with
  optional `N.M-<detail>.md` pages), an optional `glossary.md`, and a `_meta.json`
  recording the repo URL and indexed commit SHA used for every citation.

## Files

- `SKILL.md` — operating principles, output structure, inputs, and phased workflow
- `references/` — `DIAGRAMS.md` (Mermaid patterns) and `TEMPLATES.md` (page templates)

## Related

- Uses the `wiki-page-writer` subagent (in the plugin's `agents/`) during the
  parallel fan-out phase to produce one page per subsystem.
