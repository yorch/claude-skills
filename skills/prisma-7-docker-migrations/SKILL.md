---
name: prisma-7-docker-migrations
description: |
  Run Prisma 7 migrations inside a multi-stage Docker production image. Use when:
  (1) `prisma migrate deploy` crashes with "Cannot resolve environment variable: DATABASE_URL"
  or "cannot find module" at container startup, (2) building a production Docker image
  that needs to run migrations before starting the server, (3) you copied only
  node_modules/prisma + node_modules/@prisma but the Prisma 7 CLI still fails with
  MODULE_NOT_FOUND at runtime, (4) Yarn 4 node-modules linker .bin/prisma symlink breaks
  after Docker COPY. Covers prisma.config.ts (Prisma 7), full node_modules copy requirement,
  and symlink recreation pattern.
author: Claude Code
version: 1.0.0
date: 2026-03-14
---

# Prisma 7 in Docker Production Images

## Problem

Prisma 7 changed how datasource URLs are configured and significantly expanded the CLI's
runtime dependency closure. Two things that worked in Prisma 5/6 break silently in Prisma 7:

1. `url = env("DATABASE_URL")` in `schema.prisma` is **no longer valid** — Prisma 7 moves
   this to `prisma.config.ts` via `defineConfig()`.
2. Selectively copying only `node_modules/prisma` + `node_modules/@prisma` is **not enough**
   — Prisma 7 CLI loads additional packages at runtime that aren't in those scopes.

Additionally, Yarn 4 node-modules linker creates `.bin/prisma` as a **symlink**. Docker `COPY`
dereferences symlinks, silently converting the symlink to a regular file at the wrong location,
breaking WASM engine loading.

## Context / Trigger Conditions

- Prisma 7+ with a multi-stage Dockerfile
- Yarn 4 with `nodeLinker: node-modules`
- Container crashes at startup with any of:
  - `PrismaConfigEnvError: Cannot resolve environment variable: DATABASE_URL`
  - `Error: Cannot find module '@prisma/config'`
  - `Error: Cannot find module 'effect'`
  - `Error: WASM file not found` or similar engine loading errors
- `prisma validate` passes locally but fails in the container

## Root Causes

### Root Cause 1: `schema.prisma` no longer holds the datasource URL

In Prisma 7, `datasource db { url = env("DATABASE_URL") }` was removed from `schema.prisma`.
The URL now lives in `prisma.config.ts`:

```typescript
// packages/server/prisma.config.ts
import { defineConfig, env } from 'prisma/config'

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: { path: 'prisma/migrations' },
  datasource: { url: env('DATABASE_URL') },
})
```

### Root Cause 2: Prisma 7 CLI has a large non-bundled dependency closure

Prisma 7 CLI requires at runtime (beyond `prisma` and `@prisma`):
- `effect`
- `fast-check`
- `pure-rand`
- `@prisma/config`
- Other transitive deps

Selective copying of `node_modules/prisma` + `node_modules/@prisma` misses these.

### Root Cause 3: Docker COPY dereferences Yarn 4 `.bin/` symlinks

In Yarn 4 node-modules linker, `.bin/prisma` is a symlink to
`../prisma/build/index.js` (relative path). Docker `COPY` follows the symlink and
copies the **file content** to the destination, preserving `__dirname` as the *source*
directory — not the destination. This breaks WASM loading which is relative to `__dirname`.

## Solution

### Step 1: Copy `prisma.config.ts` from the build stage

```dockerfile
COPY --from=build-server /app/packages/server/prisma ./prisma
COPY --from=build-server /app/packages/server/prisma.config.ts ./prisma.config.ts
```

### Step 2: Copy full `node_modules` (until a deps-prod stage is available)

```dockerfile
# Prisma 7 CLI requires its full transitive dependency closure at runtime.
# TODO: Introduce a deps-prod stage (yarn workspaces focus server --production
# after adding @yarnpkg/plugin-workspace-tools) to reduce image size.
COPY --from=deps /app/node_modules ./node_modules
```

### Step 3: Recreate the `.bin/prisma` symlink after COPY

```dockerfile
# Yarn 4 .bin/prisma is a symlink that Docker COPY dereferences. Recreate it so
# __dirname resolves to prisma/build/ for correct WASM engine loading.
RUN ln -sf /app/node_modules/prisma/build/index.js /app/node_modules/.bin/prisma
```

### Step 4: Add `node_modules/.bin` to PATH and update CMD

```dockerfile
ENV PATH="/app/node_modules/.bin:$PATH"

CMD ["sh", "-c", "prisma migrate deploy && node server/index.mjs"]
```

### Step 5: Move `prisma` from devDependencies to dependencies

In `packages/server/package.json`, move `prisma` to `dependencies` so the runtime
requirement is explicit and won't silently break if the install strategy changes:

```json
{
  "dependencies": {
    "prisma": "7.x.x"
  }
}
```

## Complete Production Stage Example

```dockerfile
# ── Production ───────────────────────────────────────────────────
FROM node:22-alpine AS production
WORKDIR /app

COPY --from=build-server /app/packages/server/dist ./server
COPY --from=build-web /app/packages/web/dist ./web

# Prisma: schema + migrations + config (Prisma 7 uses prisma.config.ts for datasource URL)
COPY --from=build-server /app/packages/server/prisma ./prisma
COPY --from=build-server /app/packages/server/prisma.config.ts ./prisma.config.ts

# Prisma 7 CLI requires its full transitive dependency closure at runtime.
# TODO: Introduce a deps-prod stage (yarn workspaces focus server --production
# after adding @yarnpkg/plugin-workspace-tools) to reduce image size.
COPY --from=deps /app/node_modules ./node_modules

# Yarn 4 .bin/prisma is a symlink that Docker COPY dereferences. Recreate it so
# __dirname resolves to prisma/build/ for correct WASM engine loading.
RUN ln -sf /app/node_modules/prisma/build/index.js /app/node_modules/.bin/prisma

ENV PATH="/app/node_modules/.bin:$PATH"
ENV NODE_ENV=production
EXPOSE 4000

CMD ["sh", "-c", "prisma migrate deploy && node server/index.mjs"]
```

## Verification

Run the production image without `DATABASE_URL` — it should fail with a clear
Prisma config error (not a Node.js module error):

```bash
docker build -t test:local .
docker run --rm test:local
# Expected: PrismaConfigEnvError: Cannot resolve environment variable: DATABASE_URL
# NOT: Error: Cannot find module '...'
```

If you see `Cannot find module`, the dependency closure is still incomplete.

## Future Optimization (Image Size)

The full `node_modules` copy significantly inflates the image. The correct long-term fix:

1. Add `@yarnpkg/plugin-workspace-tools` to Yarn plugins
2. Add a `deps-prod` stage: `RUN yarn workspaces focus server --production`
3. Copy only Prisma-required packages from that stage

Until then, the full copy is the reliable approach.

## Notes

- Prisma 7's `.ts` config files are executed by the CLI's internal TypeScript loader
  — `tsx` is NOT required in the production image
- The `restart: unless-stopped` Docker compose policy will cause a crash-loop if
  `prisma migrate deploy` fails — set a `start_period` on your healthcheck and
  monitor logs
- `prisma` should be in `dependencies`, not `devDependencies`, since it runs at
  container startup

## References

- [Upgrade to Prisma ORM 7](https://www.prisma.io/docs/orm/more/upgrade-guides/upgrading-versions/upgrading-to-prisma-7)
- [Prisma Config Reference](https://www.prisma.io/docs/orm/reference/prisma-config-reference)
- [DOCKER | PRISMA 7: prisma.config.ts doesn't have the node_modules it needs](https://github.com/prisma/prisma/discussions/28759)
