---
name: postgres-18-docker-volume
description: >
  Catches and fixes the PostgreSQL 18 Docker volume path breaking change.
  Invoke this skill whenever you see a docker-compose.yml (or Dockerfile, or any
  container config) that uses a postgres image — especially postgres:18, postgres:18-alpine,
  or any version ≥ 18 — with a volume or bind mount. Also trigger when a user asks about
  postgres data persistence, docker compose postgres setup, volume mounts for postgres,
  migrating from postgres 17 to 18, or "my postgres data disappeared". The wrong mount
  path causes silent data loss — the skill explains what changed, how to verify the current
  mount, and how to migrate safely.
version: 1.0.0
---

## What changed in PostgreSQL 18

PostgreSQL 17 and earlier Docker images declared their persistent storage at:

```
VOLUME /var/lib/postgresql/data
```

PostgreSQL 18 changed this. The official `postgres:18` (and `postgres:18-alpine`) images now declare:

```
VOLUME /var/lib/postgresql
```

And `PGDATA` was moved from `/var/lib/postgresql/data` to `/var/lib/postgresql/18/docker`.

## Why this causes silent data loss

Docker's VOLUME instruction means: "this path needs persistent storage." When you add a
bind mount (e.g., `./data/postgres:/var/lib/postgresql/data`) for a postgres:18 container,
Docker sees it as mounting a **different** path than the one declared in VOLUME. So Docker
silently creates an anonymous volume at `/var/lib/postgresql` — the real data goes there,
not into your bind mount. Everything appears to work: migrations run, seeds succeed, the
app connects. But the data is in a randomly-named ephemeral volume, not where you think.

The failure mode is usually discovered at the worst moment: after `docker compose down -v`,
a `docker volume prune`, or a fresh `docker compose up` that starts with an empty database.

## Correct volume paths by version

This applies to **both bind mounts and named volumes** — the target path inside the container
determines where Docker routes the data.

| Postgres version | Correct volume target (bind mount or named volume) |
|---|---|
| 15, 16, 17 | `/var/lib/postgresql/data` |
| 18+ | `/var/lib/postgresql` |

**For postgres:18-alpine and postgres:18:**

```yaml
# Correct (bind mount)
volumes:
  - ./data/postgres:/var/lib/postgresql

# Correct (named volume)
volumes:
  - postgres_data:/var/lib/postgresql

# Wrong for either type (silent data loss — data goes to anonymous volume)
volumes:
  - ./data/postgres:/var/lib/postgresql/data
  # or
  - postgres_data:/var/lib/postgresql/data
```

**For postgres:17-alpine and earlier:**

```yaml
# Correct (bind mount)
volumes:
  - ./data/postgres:/var/lib/postgresql/data

# Correct (named volume)
volumes:
  - postgres_data:/var/lib/postgresql/data
```

## How to verify which path a postgres image uses

```bash
# Check the VOLUME declaration for any postgres image
docker inspect postgres:18-alpine | jq '.[0].Config.Volumes'
# → { "/var/lib/postgresql": {} }   ← PG18: mount here

docker inspect postgres:17-alpine | jq '.[0].Config.Volumes'
# → { "/var/lib/postgresql/data": {} }   ← PG17: mount here
```

If Docker is not available, check the Dockerfile on Docker Hub:
- For postgres:18+, search for `VOLUME /var/lib/postgresql` (no `/data` suffix)

## Reviewing a docker-compose file

When you see a postgres service, verify:

1. What image tag is used? If it's `postgres:18`, `postgres:18-alpine`, or newer, the target
   must be `/var/lib/postgresql`.
2. Is there a bind mount or named volume? Check the **target path** (the right side of the `:`).
   It must match the version table above. Both bind mounts and named volumes are affected —
   the target path is what matters, not the volume type.

Named volumes do NOT automatically use the correct path. Docker mounts them wherever you
specify. If you write `postgres_data:/var/lib/postgresql/data` against postgres:18, Docker
creates an anonymous volume at `/var/lib/postgresql` (the VOLUME-declared path) and mounts
`postgres_data` at the wrong subdirectory. PG18 writes to the anonymous volume, not to
`postgres_data`.

Flag any mismatch. Silently wrong mounts are worse than errors — they give no warning.

## Migrating existing data from PG17 → PG18

If a user is upgrading from postgres:17 to postgres:18 and already has data:

1. **Do not just change the mount path.** PostgreSQL 18 uses a new on-disk format — you
   must `pg_dump` / `pg_restore` across major versions, not just remount.
2. Dump from the running PG17 container:
   ```bash
   docker exec -t <pg17-container> pg_dumpall -U <user> > dump.sql
   ```
3. Stop PG17, switch image to postgres:18, **update the volume mount path** to
   `/var/lib/postgresql`, bring it up fresh, then restore:
   ```bash
   docker exec -i <pg18-container> psql -U <user> < dump.sql
   ```
4. Verify data integrity before removing the old volume.

## Quick-fix checklist

When reviewing or writing a docker-compose file with postgres:18+:

- [ ] Volume target is `/var/lib/postgresql` (not `/var/lib/postgresql/data`)
- [ ] `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` are set (required for healthcheck)
- [ ] Healthcheck uses `pg_isready -U <user>` so dependent services wait for readiness
- [ ] Data directory in the host path is separate from previous major-version data
      (postgres 18 data is not backward-compatible with postgres 17)
