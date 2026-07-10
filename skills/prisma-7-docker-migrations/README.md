# prisma-7-docker-migrations

Fixes the failures that appear when running Prisma 7 `migrate deploy` inside a
multi-stage Docker production image. Prisma 7 moved the datasource URL out of
`schema.prisma` into `prisma.config.ts`, expanded the CLI's runtime dependency
closure well beyond `prisma` + `@prisma`, and interacts badly with Yarn 4's
`.bin/prisma` symlink once Docker `COPY` dereferences it.

## When to use

- `prisma migrate deploy` crashes at container startup with
  `Cannot resolve environment variable: DATABASE_URL` or `Cannot find module`
- Building a production image that must run migrations before starting the server
- You copied only `node_modules/prisma` + `node_modules/@prisma` but the CLI
  still fails with `MODULE_NOT_FOUND`
- The Yarn 4 node-modules linker `.bin/prisma` symlink breaks after `COPY`

## What it fixes

- The three root causes: `prisma.config.ts` datasource setup, copying the full
  `node_modules` the Prisma 7 CLI needs at runtime, and recreating the `.bin`
  symlink so the WASM engine loads correctly.

## Files

- `SKILL.md` — root-cause analysis and the corrected Dockerfile pattern
