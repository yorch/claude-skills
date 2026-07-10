# app-docker-deploy-with-traefik

Generates production-ready Docker deployment configuration for any application,
wired for a [Traefik](https://traefik.io/) reverse proxy with automatic HTTPS via
Let's Encrypt. It detects the project type (Node.js, Python, Go, Rust, Java),
picks a sensible port, and emits a composable set of files that follow proven
production patterns (multi-stage builds, non-root user, healthchecks, persistent
volumes).

## When to use

- Dockerize / containerize an app, or add a `Dockerfile`
- Set up `docker-compose` for local or production
- Deploy behind Traefik, add a reverse proxy, or configure HTTPS/SSL and
  Let's Encrypt certificates

## What it produces

- `Dockerfile` — multi-stage build tailored to the detected stack
- `docker-compose.yml` — base service definitions with volumes and healthchecks
- `docker-compose.for-traefik.yml` — Traefik routing overlay (composed on top)
- `.env.sample` — environment variable template

## Files

- `SKILL.md` — full workflow and step-by-step instructions
- `DOCKERFILES.md` — Dockerfile templates per language
- `EXAMPLES.md` — worked configuration examples
- `templates/` — starter `Dockerfile.*` and `docker-compose*.yml` files
- `scripts/` — helpers: network check, htpasswd generation, compose validation
