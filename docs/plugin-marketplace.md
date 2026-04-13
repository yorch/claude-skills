# Claude Code Plugin & Marketplace Structure

Reference documentation for how this repo is structured as a Claude Code plugin marketplace.

## Key Concepts

A Claude Code **plugin** bundles skills, commands, agents, hooks, and MCP servers into an installable unit.

A Claude Code **marketplace** is a catalog (defined by `marketplace.json`) that lists one or more plugins and where to find them. Every repo that acts as a marketplace must have `.claude-plugin/marketplace.json`.

These two files live together in `.claude-plugin/` at the repo root:

| File                              | Purpose                                                                     |
| --------------------------------- | --------------------------------------------------------------------------- |
| `.claude-plugin/plugin.json`      | Describes *this plugin* (name, version, author, etc.)                       |
| `.claude-plugin/marketplace.json` | Describes *this marketplace* and lists available plugins with their sources |

## This Repo's Structure

```text
claude-skills/
├── .claude-plugin/
│   ├── marketplace.json   ← marketplace catalog (lists claude-skills plugin at "./")
│   └── plugin.json        ← plugin manifest
├── .github/
│   └── workflows/
│       └── validate.yml   ← CI: validates manifest + skill structure
├── skills/                ← auto-discovered by Claude Code
│   ├── app-docker-deploy-with-traefik/
│   │   └── SKILL.md
│   ├── code-changes-review/
│   │   └── SKILL.md
│   └── ...
└── docs/
```

## marketplace.json Schema

Minimal required fields:

```json
{
  "name": "marketplace-name",   // kebab-case; becomes @marketplace-name in install commands
  "owner": { "name": "Your Name" },
  "plugins": [
    {
      "name": "plugin-name",    // becomes plugin-name@marketplace-name
      "source": "./"            // "./" = plugin is at repo root
    }
  ]
}
```

### Plugin source types

| Source        | Example                                                           | Notes                                                |
| ------------- | ----------------------------------------------------------------- | ---------------------------------------------------- |
| Relative path | `"./plugins/my-plugin"`                                           | Plugin in same repo. Resolves from marketplace root. |
| Root of repo  | `"./"`                                                            | Plugin IS the repo root (single-plugin repos)        |
| GitHub repo   | `{ "source": "github", "repo": "owner/repo" }`                    | External plugin repo                                 |
| Git URL       | `{ "source": "url", "url": "https://..." }`                       | Any git host                                         |
| Subdirectory  | `{ "source": "git-subdir", "url": "...", "path": "plugins/foo" }` | Sparse clone of a monorepo subdir                    |
| npm           | `{ "source": "npm", "package": "@scope/plugin" }`                 | npm package                                          |

### Single-plugin vs multi-plugin repos

**Single-plugin** (this repo's pattern — plugin at repo root):

```json
{
  "plugins": [{ "name": "claude-skills", "source": "./" }]
}
```

**Multi-plugin** (plugin subdirectories, like `anthropics/claude-plugins-official`):

```json
{
  "metadata": { "pluginRoot": "./plugins" },
  "plugins": [
    { "name": "plugin-a", "source": "plugin-a" },
    { "name": "plugin-b", "source": "plugin-b" }
  ]
}
```

## Installation

```bash
# Add this repo as a marketplace (once per machine)
/plugin marketplace add yorch/claude-skills

# Install the plugin
/plugin install claude-skills@yorch

# Update after new skills are pushed
/plugin update claude-skills@yorch
```

For local development (without pushing to GitHub):

```bash
/plugin install /Users/yorch/code-personal/claude-skills
```

## Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter
2. Add a temporary symlink for local development:

   ```bash
   ln -s "$(pwd)/skills/<skill-name>" ~/.claude/skills/<skill-name>
   ```

3. Reinstall the plugin when ready: `/plugin install claude-skills@yorch`
4. Remove the symlink after reinstall

## References

- [Claude Code: Create plugins](https://code.claude.com/docs/en/plugins)
- [Claude Code: Create and distribute a plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
- [Claude Code: Discover and install plugins](https://code.claude.com/docs/en/discover-plugins)
