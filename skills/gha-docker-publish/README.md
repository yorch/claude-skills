# gha-docker-publish

Generates a GitHub Actions workflow that builds and publishes Docker images
using a set of opinionated, hard-to-guess conventions: `datetime+SHA` image tags
for traceable rollbacks, a safe dry-run default on manual dispatch, a
`publish-docker` PR label gate, conditional `latest` on the default branch only,
GHA layer caching with `mode=max`, and dual-registry (GHCR + private) push
patterns.

## When to use

- Set up GHCR publishing or add a `docker-publish.yml` workflow
- Add layer caching to Docker CI, or configure datetime/SHA image tags
- Add a manual build-only dispatch trigger, push to multiple registries, or
  build Docker images on pull requests

## What it produces

- A complete GitHub Actions workflow YAML implementing the conventions above,
  ready to drop into `.github/workflows/`.

## Files

- `SKILL.md` — the complete workflow and the rationale behind each convention
