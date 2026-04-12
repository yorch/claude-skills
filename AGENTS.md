# Project Guidelines

This file provides guidance to AI Agents when working with code in this repository.

## Repository Overview

This is a collection of reusable Claude AI skills - structured instruction sets that help Claude perform specific, complex tasks consistently. Each skill is a self-contained directory with documentation, templates, and helper scripts.

The documentation for Claude Skills can be found at <https://code.claude.com/docs/en/skills>. You can reference this when working with the code.

## Architecture

```text
claude-skills/
├── README.md                          # Project overview
├── LICENSE                            # MIT License
└── skills/                            # All skills live here
    └── <skill-name>/                  # Each skill is a directory
        ├── SKILL.md                   # Main instructions (frontmatter + workflow)
        ├── templates/                 # Reusable file templates
        ├── scripts/                   # Helper utilities
        └── *.md                       # Supporting documentation
```

## Plugin

This repository is a Claude Code plugin. The plugin manifest is at `.claude-plugin/plugin.json`. Skills in `skills/` are auto-discovered by Claude Code — no explicit registration needed.

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

## Available Skills

### app-docker-deploy-with-traefik

Generates Docker + Traefik deployment configurations for any application type.

**Output files:**

- `Dockerfile` - Multi-stage build for the detected project type
- `docker-compose.yml` - Base service definitions
- `docker-compose.for-traefik.yml` - Traefik routing overlay (composable)
- `.env.sample` - Environment variable template

**Helper scripts:**

```bash
# Generate htpasswd hash for basic auth
./skills/app-docker-deploy-with-traefik/scripts/generate-htpasswd.sh admin mypassword

# Validate compose files
python skills/app-docker-deploy-with-traefik/scripts/validate-compose.py docker-compose.yml

# Check/create traefik network
./skills/app-docker-deploy-with-traefik/scripts/check-network.sh --create
```

**Validation script requires:** `pip install pyyaml`

### code-changes-review

Performs comprehensive code review of uncommitted changes in a git repository.

**Review dimensions:**

- **Correctness** - Logic errors, bugs, edge cases
- **Security** - Vulnerabilities, injection risks, sensitive data exposure
- **Best Practices** - Language idioms, framework conventions
- **DRY/Reusability** - Code duplication, abstraction opportunities
- **Code Smells** - Maintainability issues, complexity, coupling
- **Performance** - N+1 queries, memory leaks, inefficiencies
- **Testing** - Coverage gaps, test quality

**Review modes:**

- Default - Quick review focusing on critical issues
- `--thorough` - Complete analysis including style and documentation
- `--security` - Deep dive into OWASP Top 10 and security practices
- `--performance` - Focus on efficiency and resource usage

**Supporting files:**

- [CHECKLIST.md](./skills/code-changes-review/CHECKLIST.md) - Detailed review criteria with examples

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
