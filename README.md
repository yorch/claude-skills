# Claude Skills

A collection of reusable skills for Claude AI to help with common development tasks.

## What are Skills?

Skills are structured instruction sets that help Claude perform specific, complex tasks consistently. Each skill contains:

- **SKILL.md** - Main instructions and workflow for the skill
- **Supporting files** - Templates, examples, and reference documentation

## Available Skills

| Skill                                                               | Description                                                                                                                                                                              |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [app-docker-deploy-with-traefik](./skills/app-docker-deploy-with-traefik/) | Generate Docker and Traefik deployment configuration for any application (Node.js, Python, Go, etc). Creates Dockerfile, docker-compose.yml, Traefik overlay, and environment templates. |
| [code-changes-review](./skills/code-changes-review/)                       | Comprehensive code review of uncommitted git changes. Analyzes for bugs, security issues, best practices, DRY violations, code smells, and performance problems.                         |

## Usage

These skills are designed to be used with Claude in your development workflow. Reference the skill directory when asking Claude to perform a related task, and it will follow the structured instructions to deliver consistent, production-ready results.

## Contributing

Feel free to submit pull requests with new skills or improvements to existing ones.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
