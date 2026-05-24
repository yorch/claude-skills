---
name: repo-wiki-generator
description: >
  Generate a DeepWiki-style structured wiki for any git repository: an
  Overview page, one page per detected subsystem, and detail pages for
  major components, with Mermaid architecture diagrams and commit-pinned
  source citations. Uses parallel subagents to fan out per-page
  generation. Output goes to a configurable directory (default ./wiki/)
  inside the target repo. Use when: generate wiki, document a codebase,
  auto-generate docs, deepwiki, codebase walkthrough, architecture
  overview, onboarding documentation, repository documentation,
  document open-source repo, generate ARCHITECTURE.md, build a code map.
  Works on any language and any repo size; reads code only, never
  modifies source.
---

# Repo Wiki Generator

Produce a DeepWiki-style wiki for the current git repository: a multi-page reference with architecture diagrams, subsystem walkthroughs, and verifiable source citations. Output is written to `./wiki/` (or a configurable directory) inside the target repo.

The goal is **a navigable codebase reference**, not API docs or a tutorial. Optimized for engineers onboarding to an unfamiliar codebase.

## Operating principles

- **Read-only on the target repo.** Never edit source code. The deliverable is the `./wiki/` directory.
- **Pin every citation to a single commit SHA.** Capture `git rev-parse HEAD` once at the start of the run and use it for every generated URL. This makes links immutable even after the upstream code changes.
- **Earn every claim with a citation.** Every section ends with a `Sources:` footer listing the files it draws from. Inline claims about specific behavior must cite a file path with line numbers.
- **Don't fabricate diagrams.** If subsystem boundaries are unclear from the code, skip the diagram for that page rather than invent structure that isn't there.
- **Reuse existing docs as input, don't reinvent them.** Read README, ARCHITECTURE.md, CONTRIBUTING.md, and any `docs/` content if present. Cross-reference them rather than restating them.
- **Skip generated / vendor code.** Respect `.gitignore`. Always exclude: `node_modules/`, `vendor/`, `dist/`, `build/`, `out/`, `.next/`, `target/`, `coverage/`, `.turbo/`, `__pycache__/`, `.venv/`.
- **Verify line ranges before citing.** A citation to `file:1-50` is only valid if the file has at least 50 lines. Spot-check before writing.

## Output structure

The wiki directory has this layout (numeric prefixes encode hierarchy and ordering, same convention as DeepWiki):

```text
wiki/
├── README.md                                 # Overview page + index
├── _SIDEBAR.md                               # Hierarchical nav for browsing
├── 1-repository-structure.md                 # Repo layout, packages, build
├── 2-<subsystem-slug>.md                     # One per detected subsystem
│   ├── 2.1-<detail-slug>.md                  # Optional detail pages
│   └── 2.2-<detail-slug>.md
├── 3-<next-subsystem-slug>.md
└── glossary.md                               # Optional; only if domain terms detected
```

The Overview page (`README.md`) is the wiki's entry point. It includes the repo identity, indexed commit SHA, high-level architecture, repo layout, and links to every other page.

## Inputs

If the user supplies any of these, honor them; otherwise use defaults:

- `output_dir` — default `./wiki/`
- `scope` — default `full` (overview + subsystems + details). Other values: `subsystems` (skip details), `overview` (just `README.md`).
- `max_subsystems` — default `12`. Cap to avoid runaway generation on huge monorepos.
- `include_glossary` — default `auto` (include if domain-specific jargon detected).

## Workflow

### Phase 1 — Discover the repo (single agent, main thread)

1. **Identify the repo.** Run `git remote get-url origin` to derive the canonical GitHub/GitLab URL. Normalize SSH form (`git@github.com:owner/repo.git`) to HTTPS (`https://github.com/owner/repo`).
2. **Pin the commit.** Run `git rev-parse HEAD` and store the short SHA. Every citation URL must use this SHA. Also capture `git log -1 --format=%cI` for the indexed-at timestamp.
3. **Detect language and stack.** Read whichever exists: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `build.gradle`, `composer.json`, `pubspec.yaml`. Record primary language, framework, package manager, current version (from manifest), and test runner.
4. **Read existing docs.** If `README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, or `docs/` exist, read them. These become _inputs_ — quote/cite them rather than restate.
5. **Map the file tree.** Capture top 3 levels of the repo tree, respecting `.gitignore`. Use `git ls-files | head -500` for a representative sample on very large repos.
6. **Write a `_meta.json` to the output dir** with: `{ repo_url, commit_sha, indexed_at, primary_language, framework, version, subsystems: [] }`. This is the source of truth for citation URLs in all later phases.

### Phase 2 — Identify subsystems (single agent, main thread)

Subsystems are the top-level units the wiki will document. Detection rules, in priority order:

1. **Monorepo packages.** If `packages/*`, `apps/*`, `workspaces/*`, or a workspace field in `package.json` / `Cargo.toml` / `pnpm-workspace.yaml` exists, each package is a subsystem.
2. **Top-level source dirs.** Otherwise, each meaningful directory under `src/`, `lib/`, `app/`, `internal/`, `pkg/`, or the repo root is a subsystem. Ignore generic buckets like `utils/`, `helpers/`, `common/` unless they're substantial (>20 files).
3. **Convention-based.** For framework projects, follow framework conventions: Next.js (`app/`, `pages/`, `components/`, `lib/`), Rails (`app/models`, `app/controllers`, `app/services`), Django (apps), etc.

For each subsystem, record: `{ slug, name, paths[], file_count, loc_estimate, has_tests }`. Cap at `max_subsystems` — if the repo exceeds the cap, merge the smallest subsystems into a single "Other modules" page.

Save the subsystem list to `_meta.json`.

### Phase 3 — Plan pages (single agent, main thread)

Build the page list:

- **1 Overview page** (`README.md`) — always.
- **1 Repository Structure page** (`1-repository-structure.md`) — always; covers layout, build, packages.
- **N Subsystem pages** (`{i}-{slug}.md`) — one per subsystem from Phase 2.
- **Detail pages** (`{i}.{j}-{slug}.md`) — only when `scope=full` AND the subsystem has either >40 files or >2 clearly distinct concerns (e.g., "data layer" + "transport" inside one service).
- **Glossary** (`glossary.md`) — only if `include_glossary=auto` detects ≥10 domain-specific terms.

Write the full page plan to `_meta.json` as `pages: [{ slug, type, sources_hint: [paths...] }]`. This is the dispatch table for Phase 4.

### Phase 4 — Generate pages in parallel (subagent fan-out)

This is the core of the skill. Dispatch the **`wiki-page-writer`** agent (defined in this plugin's `agents/` directory) — one invocation per page, all sent in a single message so they run in parallel. Use `subagent_type: wiki-page-writer`.

Skip the Overview page here; it's generated last in Phase 5 so it can cross-link the subsystem pages that this phase produces.

The `wiki-page-writer` agent already knows the templates, citation rules, voice conventions, and constraints — its system prompt embeds them. Your dispatch prompt only needs to supply the per-page inputs.

**Per-page dispatch prompt:**

```text
output_path: {abs_output_dir}/{slug}.md
page_type: {category | detail}
subsystem_name: {name}
source_paths:
  - {path1}
  - {path2}
commit_sha: {short_sha}
repo_url: {https_repo_url}
skill_dir: {abs_path_to_repo_wiki_generator_skill}
related_pages:                          # optional
  - parent: {parent_slug}
  - siblings: [{sibling_slug}, ...]
```

The agent returns the absolute path of the file it wrote, or a single line beginning with `ERROR:` if it could not complete. Collect all returned paths; you'll need them in Phase 5 for validation and nav generation.

**Dispatch all pages in parallel** — make N Agent calls in one message, where N is the number of non-Overview pages from Phase 3. Independence is the whole point; sequential dispatch wastes the parallelism.

If you need to consult the agent's full contract (tool allowlist, output format, error conventions), read `agents/wiki-page-writer.md` at the plugin root.

### Phase 5 — Assemble Overview, nav, and validate (main thread)

After all subagents return:

1. **Generate `README.md` (Overview).** Now that subsystem pages exist, the Overview can cross-link them confidently. Follow the overview template in `references/TEMPLATES.md`. Include a Mermaid high-level architecture diagram showing all subsystems and their primary relationships.
2. **Generate `_SIDEBAR.md`** — a hierarchical nav listing every page. This is what humans browse.
3. **Validate citations.** Scan all generated `.md` files for citation URLs. For each, confirm the cited path exists in the repo at the indexed SHA, and the line range is within file bounds. Drop or fix broken citations.
4. **Append generation metadata** to the Overview footer:

   ```markdown
   ---

   _Generated by `repo-wiki-generator` on {date} from commit `{sha}`._
   ```

5. **Report a summary** to the user: pages written, total citations, any dropped citations, suggested next steps (e.g., commit the wiki, set up CI to refresh on schedule).

## Citation format (canonical reference)

Inline (within prose):

```text
[packages/foo/src/index.ts#L42](https://github.com/{owner}/{repo}/blob/{sha}/packages/foo/src/index.ts#L42)
```

Range (in `Sources:` footer):

```text
Sources: [packages/foo/src/index.ts:L1-L80](url) [packages/foo/src/parser.ts:L120-L200](url)
```

Multiple sources separated by single spaces, no commas. See `references/TEMPLATES.md` for full examples.

## When NOT to use this skill

- For **public API documentation** — use docs generators specific to the language (TypeDoc, Sphinx, rustdoc, etc.). DeepWiki-style wikis document the _codebase_, not the published interface.
- For **product user docs** — Mintlify, Docusaurus, and the project's own docs site are the right tools.
- For **changelogs** — `git log` and GitHub Releases already do this well.
- On a **branch with significant uncommitted changes** — citations would point to commit state that doesn't match the current working tree. Commit or stash first, or accept that the wiki reflects HEAD-as-committed.

## Future enhancements (not in v1)

- **Refresh mode.** Re-run only on subsystems whose files have changed since the last `_meta.json.commit_sha`. Significant cost savings on incremental updates.
- **Diff mode.** Generate a per-page diff against the previous commit to highlight what changed.
- **CI integration.** A GitHub Action that runs the skill weekly and commits the wiki updates as a PR.
