# postgres-18-docker-volume

Catches and fixes the PostgreSQL 18 Docker volume path breaking change. In
Postgres 18 the image's declared `VOLUME` moved from `/var/lib/postgresql/data`
to `/var/lib/postgresql` (and `PGDATA` moved to `/var/lib/postgresql/18/docker`).
Reusing the old mount path routes data into an anonymous volume instead of your
bind mount or named volume — everything appears to work until a `down -v`,
`volume prune`, or fresh `up` reveals the database is empty. **Silent data loss.**

## When to use

- Any `docker-compose.yml` / Dockerfile / container config using a
  `postgres:18` (or newer) image with a volume or bind mount
- Questions about postgres data persistence or compose volume mounts
- Migrating from Postgres 17 to 18, or "my postgres data disappeared"

## What it fixes

- Points the volume at the correct in-container target per version
  (`/var/lib/postgresql/data` for ≤17, `/var/lib/postgresql` for 18+) and
  explains how to verify the current mount and migrate existing data safely.

## Files

- `SKILL.md` — what changed, why it loses data, correct paths, and migration
- `evals/` — evaluation cases (`evals.json`) exercising the fix
