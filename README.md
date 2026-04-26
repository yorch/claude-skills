# Claude Skills

A collection of reusable skills for Claude AI to help with common development tasks.

## What are Skills?

Skills are structured instruction sets that help Claude perform specific, complex tasks consistently. Each skill contains:

- **SKILL.md** - Main instructions and workflow for the skill
- **Supporting files** - Templates, examples, and reference documentation

## Available Skills

| Skill                                                                      | Description                                                                                                                                                                              |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [app-docker-deploy-with-traefik](./skills/app-docker-deploy-with-traefik/)             | Generate Docker and Traefik deployment configuration for any application (Node.js, Python, Go, etc). Creates Dockerfile, docker-compose.yml, Traefik overlay, and environment templates. |
| [code-changes-review](./skills/code-changes-review/)                                   | Comprehensive code review of uncommitted git changes. Analyzes for bugs, security issues, best practices, DRY violations, code smells, and performance problems.                         |
| [gha-docker-publish](./skills/gha-docker-publish/)                                     | Build and publish Docker images via GitHub Actions with opinionated patterns: datetime+SHA tags, safe dry-run defaults, and PR label gates.                                               |
| [postgres-18-docker-volume](./skills/postgres-18-docker-volume/)                       | Fix the PostgreSQL 18 Docker volume path breaking change that causes silent data loss when using old mount paths from Postgres 17 and earlier.                                            |
| [prisma-7-docker-migrations](./skills/prisma-7-docker-migrations/)                     | Run Prisma 7 migrations inside a multi-stage Docker production image, fixing MODULE_NOT_FOUND and missing DATABASE_URL errors at container startup.                                       |
| [rails-auto-assigned-field-validation](./skills/rails-auto-assigned-field-validation/) | Fix Rails models where `validates :field, presence: true` silently breaks creates when the field is set by a `before_create` callback.                                                   |
| [react-app-review](./skills/react-app-review/)                                         | Thorough React/Next.js code review: simplify components, extract hooks, fix state/effect anti-patterns, improve accessibility, and produce an incremental refactor roadmap.               |
| [typescript-unknown-jsx-expression](./skills/typescript-unknown-jsx-expression/)       | Fix TypeScript "Type 'unknown' is not assignable to type ReactNode" errors in JSX `&&` short-circuit expressions using `Record<string, unknown>` values.                                 |

## Installation

Add the marketplace and install the plugin in Claude Code:

```text
/plugin marketplace add yorch/claude-skills
/plugin install claude-skills@yorch
```

Skills activate automatically based on context — no manual invocation needed.

## Contributing

Feel free to submit pull requests with new skills or improvements to existing ones.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
