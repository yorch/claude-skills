---
name: gha-docker-publish
description: |
  Generate or set up a GitHub Actions workflow that builds and publishes Docker images
  to GHCR (GitHub Container Registry) with optional dual-registry support (e.g., Docker Hub,
  private registry). Use this skill when: (1) setting up CI/CD Docker image publishing to GHCR,
  (2) adding a docker-publish.yml GitHub Actions workflow, (3) configuring conditional `latest`
  tags (only on main), (4) adding datetime+sha image tags for traceability, (5) setting up
  dual-registry push in GitHub Actions, (6) configuring GHA layer cache for Docker builds,
  (7) adding a manual workflow_dispatch trigger for Docker builds. Covers the complete workflow
  pattern using docker/metadata-action, docker/build-push-action, and GHA cache.
author: Claude Code
version: 1.0.0
date: 2026-03-15
---

# GitHub Actions: Docker Build & Publish Workflow

## When to Use This Skill

Use this pattern when you need a CI workflow that:
- Pushes Docker images to **GHCR** (and optionally a second registry)
- Tags images with a **datetime+sha** slug for traceability and rollback
- Applies `latest` **only on the default branch** (not feature branches or tags)
- Supports **manual triggering** with a push toggle (useful for dry-run builds)
- Uses **GHA layer cache** to speed up repeat builds

---

## The Complete Workflow

```yaml
name: Build and Publish Docker Image

on:
  push:
    branches:
      - main
    tags:
      - "v*"
  pull_request:
    types: [opened, synchronize, reopened, labeled]
  workflow_dispatch:
    inputs:
      push:
        description: "Push image to registries"
        required: false
        default: true
        type: boolean

env:
  GHCR_IMAGE: ghcr.io/${{ github.repository }}

permissions:
  contents: read
  packages: write

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Log in to external registry
        if: vars.EXTERNAL_REGISTRY_URL != ''
        uses: docker/login-action@v3
        with:
          registry: ${{ vars.EXTERNAL_REGISTRY_URL }}
          username: ${{ secrets.EXTERNAL_REGISTRY_USERNAME }}
          password: ${{ secrets.EXTERNAL_REGISTRY_PASSWORD }}

      - name: Get commit info
        id: commit
        run: |
          echo "datetime=$(git log -1 --format=%cd --date=format:'%Y%m%d%H%M' HEAD)" >> ${GITHUB_OUTPUT}
          echo "sha=$(git rev-parse --short HEAD)" >> ${GITHUB_OUTPUT}

      - name: Build image list
        id: images
        env:
          GHCR_IMAGE: ${{ env.GHCR_IMAGE }}
          EXTERNAL_REGISTRY_URL: ${{ vars.EXTERNAL_REGISTRY_URL }}
          EXTERNAL_REGISTRY_IMAGE: ${{ vars.EXTERNAL_REGISTRY_IMAGE }}
        run: |
          IMAGES="${GHCR_IMAGE}"
          if [[ -n "${EXTERNAL_REGISTRY_URL}" ]]; then
            IMAGE_NAME="${EXTERNAL_REGISTRY_IMAGE:-my-app}"
            IMAGES="${IMAGES}"$'\n'"${EXTERNAL_REGISTRY_URL}/${IMAGE_NAME}"
          fi
          {
            echo 'list<<EOF'
            echo "${IMAGES}"
            echo 'EOF'
          } >> "${GITHUB_OUTPUT}"

      - name: Extract Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ steps.images.outputs.list }}
          tags: |
            type=ref,event=pr
            type=raw,value=${{ steps.commit.outputs.datetime }}_${{ steps.commit.outputs.sha }},enable=${{ github.event_name != 'pull_request' }}
            type=ref,event=branch
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: >-
            ${{
              github.event_name == 'push' ||
              (github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'publish-docker')) ||
              (github.event_name == 'workflow_dispatch' && inputs.push)
            }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64
```

---

## Key Design Decisions

### Tags Generated

| Tag pattern | Example | When applied |
|---|---|---|
| `pr-N` | `pr-42` | PR events only — human-readable, identifies the PR |
| `datetime_sha` | `202603151430_a1b2c3d` | push and tag events — chronological + traceable |
| Branch name | `main` | branch push events (not tag push events) — human-readable current ref |
| `latest` | `latest` | Only on the default branch (`main`) |
| Tag ref | `v1.2.3` | Only when pushing a `v*` git tag |

The `datetime_sha` format is important: it lets you sort images chronologically in the registry UI and trace back to an exact commit without needing semver versioning.

### Why `metadata-action` for `latest` instead of shell conditionals?

`docker/metadata-action` handles the `enable={{is_default_branch}}` expression natively — `latest` is emitted only when `github.ref` matches the default branch. This is cleaner than a shell `if` block, and avoids the `|| ''` / `|| null` pitfall that causes `invalid reference format` errors (see the `gha-docker-conditional-tags` skill if you hit those issues separately).

### PR builds: build always, push only with `publish-docker` label

Every `pull_request` event (opened, pushed to, reopened, labeled) triggers the
workflow and builds the Docker image. The build serves as a validation check — it
fails fast if the Dockerfile is broken, even without pushing anything.

The image is only pushed when the `publish-docker` label is present on the PR at
the time the run starts. This is checked via:

```yaml
contains(github.event.pull_request.labels.*.name, 'publish-docker')
```

This expression reads the label set from the webhook payload at run time. If the
label was already on the PR before a new commit was pushed, that commit's build
also pushes.

**Fork PR limitation:** On `pull_request` events from forked repositories, GitHub
restricts `GITHUB_TOKEN` to read-only regardless of the `permissions:` declaration.
The `publish-docker` label check passes but the GHCR push fails with a permission
error. This is expected GHA behavior. The publish-on-label feature works only for
PRs from branches within the same repository. If the repository is public, document
this restriction for contributors so they know why labeling a fork PR will not push.

### Dual-registry support (optional)

The external registry is entirely opt-in via repository variables and secrets:
- `vars.EXTERNAL_REGISTRY_URL` — e.g., `registry.example.com` or `docker.io`
- `vars.EXTERNAL_REGISTRY_IMAGE` — image name on that registry (defaults to `my-app`)
- `secrets.EXTERNAL_REGISTRY_USERNAME` / `EXTERNAL_REGISTRY_PASSWORD`

If `EXTERNAL_REGISTRY_URL` is not set, the login step is skipped and only GHCR is used.

### GHA cache with `mode=max`

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

`mode=max` caches **all intermediate layers**, not just the final image. This is more storage-intensive but dramatically speeds up builds when dependencies or base images haven't changed.

### `workflow_dispatch` dry-run

The `push` expression:
```yaml
push: ${{ github.event_name != 'workflow_dispatch' || inputs.push }}
```
- On `push` / tag events: always pushes (expression evaluates `true`)
- On manual dispatch with `push: false`: builds but does not push (useful for testing the build)

### Permissions

```yaml
permissions:
  contents: read
  packages: write
```

`packages: write` is required to push to GHCR using `GITHUB_TOKEN`. Always scope permissions to the minimum needed.

---

## Setup Checklist

- [ ] Place file at `.github/workflows/docker-publish.yml`
- [ ] Replace `my-app` in the `Build image list` step with your actual image name (or set `EXTERNAL_REGISTRY_IMAGE` variable)
- [ ] Ensure a `Dockerfile` exists at the repo root (or set `context:` appropriately)
- [ ] If using an external registry, add these to the GitHub repo settings:
  - **Variable**: `EXTERNAL_REGISTRY_URL`
  - **Variable**: `EXTERNAL_REGISTRY_IMAGE` (optional, defaults to `my-app`)
  - **Secret**: `EXTERNAL_REGISTRY_USERNAME`
  - **Secret**: `EXTERNAL_REGISTRY_PASSWORD`
- [ ] GHCR authentication uses `GITHUB_TOKEN` automatically — no extra secrets needed

---

## Customization Points

**Multi-platform builds** — replace `platforms: linux/amd64` with:
```yaml
platforms: linux/amd64,linux/arm64
```
Note: multi-platform builds cannot use GHA cache in `mode=max` for all layers; consider `type=registry` cache instead.

**Build args** — add to the `Build and push` step:
```yaml
build-args: |
  APP_VERSION=${{ steps.commit.outputs.datetime }}_${{ steps.commit.outputs.sha }}
```

**Different default branch** — `enable={{is_default_branch}}` reads from the repository's actual default branch setting, so renaming `main` → `master` or anything else requires no change.

**Timeout** — `timeout-minutes: 30` is a reasonable default. Adjust based on your build time.
