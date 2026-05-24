# Project Guidelines

This file provides guidance to AI Agents when working with code in this repository.

> `CLAUDE.md` is a symlink to `AGENTS.md`, so any changes here will be reflected in both files.

## Repository Overview

This is a collection of reusable Claude AI skills - structured instruction sets that help Claude perform specific, complex tasks consistently. Each skill is a self-contained directory with documentation, templates, and helper scripts.

The documentation for Claude Skills can be found at <https://code.claude.com/docs/en/skills>. You can reference this when working with the code.

## Architecture

```text
claude-skills/
├── README.md                          # Project overview
├── LICENSE                            # MIT License
├── agents/                            # Specialized subagents (optional)
│   └── <agent-name>.md                # One file per agent (frontmatter + system prompt)
└── skills/                            # All skills live here
    └── <skill-name>/                  # Each skill is a directory
        ├── SKILL.md                   # Main instructions (frontmatter + workflow)
        ├── references/                # Longer reference docs the skill loads on demand
        ├── templates/                 # Reusable file templates (output artifacts)
        └── scripts/                   # Helper utilities
```

The split between `references/` and `templates/` follows Anthropic's progressive-disclosure pattern: keep `SKILL.md` short and point to `references/` for deeper material the skill (or its agents) reads at runtime. Use `templates/` for files the skill emits into the user's project.

## Plugin

This repository is a Claude Code plugin. The plugin manifest is at `.claude-plugin/plugin.json`. Skills in `skills/` and agents in `agents/` are auto-discovered by Claude Code — no explicit registration needed.

A GitHub Actions workflow at `.github/workflows/validate.yml` runs on every push and PR to `main`. It checks:

- `.claude-plugin/plugin.json` exists and is valid JSON
- Every directory under `skills/` contains a `SKILL.md`
- Every `SKILL.md` starts with YAML frontmatter (`---`)

### Skill Structure

Each skill follows this pattern:

- **SKILL.md**: YAML frontmatter (name, description, triggers) + step-by-step instructions
- **Supporting docs**: Reference materials like DOCKERFILES.md, EXAMPLES.md
- **Templates**: Starter files with `{{PLACEHOLDER}}` variables
- **Scripts**: Shell/Python utilities for common operations

## Creating New Skills

When adding a new skill:

1. Create a directory under `skills/` with a descriptive kebab-case name, then add a temporary symlink for local development:

   ```bash
   ln -s "$(pwd)/skills/<skill-name>" ~/.claude/skills/<skill-name>
   ```

   Remove the symlink once you reinstall the plugin (`/plugin install claude-skills@yorch`).
2. Add SKILL.md with YAML frontmatter:

   ```yaml
   ---
   name: skill-name
   description: >
     What the skill does and trigger keywords
   ---
   ```

3. Include step-by-step instructions in SKILL.md
4. Add templates/ for any reusable file templates
5. Add scripts/ for helper utilities
6. Update the main README.md skills table

## Creating New Agents

Agents are specialized subagents a skill (or the user) can dispatch via `subagent_type: <agent-name>`. They live in `agents/` at the plugin root, one markdown file per agent.

When adding a new agent:

1. Create `agents/<agent-name>.md` (kebab-case).
2. Add YAML frontmatter with `name`, `description`, and a tool allowlist:

   ```yaml
   ---
   name: agent-name
   description: >
     When to use this agent and what inputs it expects.
   tools: Read, Grep, Glob, Write, Bash
   ---
   ```

   The `tools` list is a constraint contract — omit `Edit` if the agent must not modify files, omit `Bash` if it must not run shell commands. Constraints expressed as missing tools are stronger than constraints expressed in prose.
3. Write the agent's system prompt below the frontmatter. Cover: required inputs, what it must do, hard rules, output contract.
4. If the agent is used by a skill, reference it from the skill's SKILL.md so the relationship is discoverable.
