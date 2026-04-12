# Plugin Transformation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `yorch/claude-skills` from a manually-symlinked skills collection into a proper Claude Code plugin with CI validation.

**Architecture:** Add a `.claude-plugin/plugin.json` manifest (required by Claude Code plugin system), add a GitHub Actions workflow that validates plugin structure on every push/PR, update docs to reflect plugin-based installation, then remove the manual symlinks and install the plugin locally.

**Tech Stack:** Claude Code plugin system, GitHub Actions, bash, Python 3 (for JSON validation in CI)

---

### Task 1: Create CI validation workflow (our "test" first)

**Files:**

- Create: `.github/workflows/validate.yml`

- [ ] **Step 1: Create the workflows directory and write the CI file**

```bash
mkdir -p .github/workflows
```

Write `.github/workflows/validate.yml`:

```yaml
name: Validate Plugin Structure

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check plugin manifest exists
        run: test -f .claude-plugin/plugin.json

      - name: Validate plugin manifest JSON
        run: python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"

      - name: Check each skill has SKILL.md
        run: |
          for dir in skills/*/; do
            skill=$(basename "$dir")
            if [ ! -f "$dir/SKILL.md" ]; then
              echo "MISSING: $dir/SKILL.md"
              exit 1
            fi
            echo "OK: $skill"
          done

      - name: Check SKILL.md files have frontmatter
        run: |
          for f in skills/*/SKILL.md; do
            if ! head -1 "$f" | grep -q "^---$"; then
              echo "MISSING frontmatter: $f"
              exit 1
            fi
            echo "OK: $f"
          done
```

- [ ] **Step 2: Run validation locally to confirm it fails without the manifest**

```bash
# Simulate the CI checks locally
test -f .claude-plugin/plugin.json && echo "manifest found" || echo "EXPECTED FAILURE: manifest missing"
```

Expected output: `EXPECTED FAILURE: manifest missing`

---

### Task 2: Create plugin manifest

**Files:**

- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create the directory and write the manifest**

```bash
mkdir -p .claude-plugin
```

Write `.claude-plugin/plugin.json`:

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

- [ ] **Step 2: Run all CI checks locally to confirm they pass**

```bash
# Check manifest exists
test -f .claude-plugin/plugin.json && echo "OK: manifest exists"

# Validate JSON
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('OK: valid JSON')"

# Check each skill has SKILL.md
for dir in skills/*/; do
  skill=$(basename "$dir")
  if [ ! -f "$dir/SKILL.md" ]; then
    echo "MISSING: $dir/SKILL.md"
    exit 1
  fi
  echo "OK: $skill"
done

# Check frontmatter
for f in skills/*/SKILL.md; do
  if ! head -1 "$f" | grep -q "^---$"; then
    echo "MISSING frontmatter: $f"
    exit 1
  fi
  echo "OK: $f"
done
```

Expected output: All lines print `OK: ...`, no failures.

---

### Task 3: Update README.md

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Replace the Usage section with plugin install instructions**

In `README.md`, find and replace the existing "Usage" section:

Old content:

```markdown
## Usage

These skills are designed to be used with Claude in your development workflow. Reference the skill directory when asking Claude to perform a related task, and it will follow the structured instructions to deliver consistent, production-ready results.
```

New content:

```markdown
## Installation

Add the marketplace and install the plugin in Claude Code:

```

/plugin marketplace add yorch/claude-skills
/plugin install claude-skills@yorch

```

Skills activate automatically based on context — no manual invocation needed.
```

- [ ] **Step 2: Verify the README renders correctly**

```bash
# Confirm the old Usage section is gone and new Installation section exists
grep -n "Installation\|marketplace add\|plugin install" README.md
```

Expected output: lines showing the three new lines present.

---

### Task 4: Update AGENTS.md

**Files:**

- Modify: `AGENTS.md`

- [ ] **Step 1: Add Plugin section after Architecture section**

In `AGENTS.md`, after the closing ` ``` ` of the Architecture code block, insert:

```markdown

## Plugin

This repository is a Claude Code plugin. The plugin manifest is at `.claude-plugin/plugin.json`. Skills in `skills/` are auto-discovered by Claude Code — no explicit registration needed.

A GitHub Actions workflow at `.github/workflows/validate.yml` runs on every push and PR to `main`. It checks:
- `.claude-plugin/plugin.json` exists and is valid JSON
- Every directory under `skills/` contains a `SKILL.md`
- Every `SKILL.md` starts with YAML frontmatter (`---`)
```

- [ ] **Step 2: Update "Creating New Skills" to mention local dev symlink**

Find the "Creating New Skills" section. Update step 1 from:

```markdown
1. Create a directory under `skills/` with a descriptive kebab-case name
```

To:

```markdown
1. Create a directory under `skills/` with a descriptive kebab-case name, then add a temporary symlink for local development:
   ```bash
   ln -s "$(pwd)/skills/<skill-name>" ~/.claude/skills/<skill-name>
   ```

   Remove the symlink once you reinstall the plugin (`/plugin install claude-skills@yorch`).

```

- [ ] **Step 3: Verify the changes look correct**

```bash
grep -n "Plugin\|symlink\|plugin install" AGENTS.md
```

Expected output: lines from both the new Plugin section and the updated Creating New Skills step.

---

### Task 5: Remove symlinks and install plugin locally

**Files:**

- Delete: 6 symlinks in `~/.claude/skills/`

- [ ] **Step 1: Remove the manual symlinks**

```bash
rm ~/.claude/skills/app-docker-deploy-with-traefik
rm ~/.claude/skills/code-changes-review
rm ~/.claude/skills/gha-docker-publish
rm ~/.claude/skills/prisma-7-docker-migrations
rm ~/.claude/skills/rails-auto-assigned-field-validation
rm ~/.claude/skills/typescript-unknown-jsx-expression
```

- [ ] **Step 2: Verify the symlinks are gone**

```bash
ls ~/.claude/skills/ | grep -E "app-docker|code-changes|gha-docker|prisma-7|rails-auto|typescript-unknown"
```

Expected output: empty (no matches).

- [ ] **Step 3: Install the plugin from the local repo path**

In Claude Code, run:

```
/plugin install /Users/yorch/code-personal/claude-skills
```

- [ ] **Step 4: Verify the plugin installed and skills are discoverable**

In Claude Code, run:

```
/plugin list
```

Expected output: `claude-skills` appears in the list.

- [ ] **Step 5: Smoke-test a skill**

Open a new Claude Code session and ask:

> "Review the uncommitted changes in this repo"

Expected behavior: the `code-changes-review` skill activates automatically.
