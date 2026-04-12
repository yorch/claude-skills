# Plugin Transformation Design

**Date:** 2026-04-12
**Status:** Approved

## Goal

Transform the `yorch/claude-skills` GitHub repository from a manually-symlinked skills collection into a proper Claude Code plugin, installable via the plugin marketplace system with CI validation.

## Approach

Single plugin (all skills bundled) with GitHub Actions validation. Skills are auto-discovered by Claude Code from the `skills/` directory — no commands or agents needed.

## Components

### 1. Plugin Manifest

New file: `.claude-plugin/plugin.json`

```json
{
  "name": "claude-skills",
  "version": "1.0.0",
  "description": "A collection of reusable skills for common development tasks — Docker/Traefik deployments, code review, Rails, TypeScript, Prisma, and GitHub Actions.",
  "author": {
    "name": "Jorge Barnaby",
    "url": "https://github.com/yorch"
  },
  "repository": "https://github.com/yorch/claude-skills",
  "license": "MIT",
  "keywords": ["docker", "rails", "typescript", "prisma", "github-actions", "code-review"]
}
```

Skills in `skills/` are auto-discovered — no explicit listing in the manifest.

### 2. Symlink Removal

The 6 manual symlinks in `~/.claude/skills/` pointing to `skills/<name>/` are removed after the plugin is installed locally. The plugin system takes over skill discovery.

Symlinks to remove:

- `~/.claude/skills/app-docker-deploy-with-traefik`
- `~/.claude/skills/code-changes-review`
- `~/.claude/skills/gha-docker-publish`
- `~/.claude/skills/prisma-7-docker-migrations`
- `~/.claude/skills/rails-auto-assigned-field-validation`
- `~/.claude/skills/typescript-unknown-jsx-expression`

All other entries in `~/.claude/skills/` (from other sources) are untouched.

### 3. CI Validation Workflow

New file: `.github/workflows/validate.yml`

Triggers: push and PR to `main`.

Validates:

1. `.claude-plugin/plugin.json` exists and is valid JSON
2. Every directory under `skills/` contains a `SKILL.md`
3. Every `SKILL.md` starts with YAML frontmatter (`---`)

### 4. Documentation Updates

**README.md** — replace "Usage" section with plugin install instructions:

```
/plugin marketplace add yorch/claude-skills
/plugin install claude-skills@yorch
```

Note that skills activate automatically based on context.

**AGENTS.md** — two changes:

1. Add a "Plugin" section documenting the manifest location and CI workflow
2. Update "Creating New Skills" to note that new skills require a temporary symlink to `~/.claude/skills/<name>` for local development until the plugin is reinstalled

## Repository Structure After

```text
claude-skills/
├── .claude-plugin/
│   └── plugin.json          ← new
├── .github/
│   └── workflows/
│       └── validate.yml     ← new
├── skills/                  ← unchanged
│   ├── app-docker-deploy-with-traefik/
│   ├── code-changes-review/
│   ├── gha-docker-publish/
│   ├── prisma-7-docker-migrations/
│   ├── rails-auto-assigned-field-validation/
│   └── typescript-unknown-jsx-expression/
├── docs/
├── AGENTS.md                ← updated
├── README.md                ← updated
├── CLAUDE.md
└── LICENSE
```

## Installation (post-implementation)

```bash
/plugin marketplace add yorch/claude-skills
/plugin install claude-skills@yorch
```

## Out of Scope

- Commands (`commands/`) — skills are auto-activated; explicit commands would be redundant
- Agents (`agents/`) — no specialized subagents needed for this collection
- Hooks (`hooks/`) — no event-driven behavior needed
- MCP servers — no external integrations
