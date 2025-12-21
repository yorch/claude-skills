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
└── <skill-name>/                      # Each skill is a directory
    ├── SKILL.md                       # Main instructions (frontmatter + workflow)
    ├── templates/                     # Reusable file templates
    ├── scripts/                       # Helper utilities
    └── *.md                           # Supporting documentation
```

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
./app-docker-deploy-with-traefik/scripts/generate-htpasswd.sh admin mypassword

# Validate compose files
python app-docker-deploy-with-traefik/scripts/validate-compose.py docker-compose.yml

# Check/create traefik network
./app-docker-deploy-with-traefik/scripts/check-network.sh --create
```

**Validation script requires:** `pip install pyyaml`

## Creating New Skills

When adding a new skill:

1. Create a directory with a descriptive kebab-case name
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
