---
name: gha-docker-conditional-tags
description: |
  Push conditional Docker image tags in GitHub Actions (e.g., `latest` only on main
  merges, not on PRs). Use when: (1) you want `latest` tag on push to main but only
  the versioned or `pr-N` tag on pull requests, (2) `|| ''` in a GHA expression produces
  "invalid reference format" errors in docker/build-push-action, (3) you want to follow
  GitHub's security hardening guide by avoiding inline `${{ context }}` interpolation in
  shell scripts. Covers shell-based tag list construction, GITHUB_OUTPUT heredoc multiline
  syntax, and env: variable security pattern.
author: Claude Code
version: 1.0.0
date: 2026-03-14
---

# GitHub Actions: Conditional Docker Tags (e.g., `latest` on main only)

## Problem

You want to push a `latest` Docker tag to a registry only on merges to `main`, but push
a different tag (e.g., `pr-N` or `sha`) on pull requests. The naive approach of using a
GHA ternary expression with `|| ''` in the `tags:` block is unreliable and violates
GitHub's security hardening recommendations.

## Context / Trigger Conditions

- Using `docker/build-push-action` with `docker/login-action`
- Want different tags on `push` vs `pull_request` events
- Seeing `invalid reference format` errors, or `"null"` literally appearing as a Docker tag
- Inline `${{ github.sha }}` or `${{ github.event_name }}` used directly in `run:` scripts

## The Wrong Approaches

### ❌ `|| ''` (blank line in tags block)

```yaml
tags: |
  ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.tag.outputs.version }}
  ${{ github.event_name == 'push' && format('...latest') || '' }}
```

A blank line may be passed as an empty tag reference to `docker/build-push-action`,
causing `invalid reference format` errors depending on the action version.

### ❌ `|| null`

```yaml
${{ github.event_name == 'push' && format('...latest') || null }}
```

GHA expressions don't have a true `null` type. Depending on context, `null` may coerce
to the literal string `"null"`, which the action tries to push as a tag named `null`.

## The Correct Approach: Shell-built tag list

Build the full tag list in the existing shell step using an `if` block, then pass it
via `$GITHUB_OUTPUT` heredoc. Reference it with `${{ steps.tag.outputs.tags }}`.

### Security note: use `env:` for context variables

GitHub's hardening guide warns against inline `${{ context }}` interpolation inside `run:`
scripts — even for seemingly safe values like `github.sha`. Always pass context values
through `env:` block variables instead.

## Solution

### Complete `Generate image tag` step

```yaml
- name: Generate image tag
  id: tag
  env:
    EVENT_NAME: ${{ github.event_name }}
    PR_NUMBER: ${{ github.event.pull_request.number }}
    GIT_SHA: ${{ github.sha }}
    REGISTRY: ${{ env.REGISTRY }}
    IMAGE_NAME: ${{ env.IMAGE_NAME }}
  run: |
    if [ "$EVENT_NAME" = "pull_request" ]; then
      VERSION="pr-${PR_NUMBER}"
    else
      TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
      SHORT_SHA=$(echo "$GIT_SHA" | cut -c1-7)
      VERSION="${TIMESTAMP}_${SHORT_SHA}"
    fi
    echo "version=${VERSION}" >> "$GITHUB_OUTPUT"

    TAGS="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    if [ "$EVENT_NAME" = "push" ]; then
      TAGS="${TAGS}"$'\n'"${REGISTRY}/${IMAGE_NAME}:latest"
    fi
    {
      echo "tags<<EOF"
      echo "$TAGS"
      echo "EOF"
    } >> "$GITHUB_OUTPUT"
```

### Updated `Build and push` step

```yaml
- name: Build and push
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ${{ steps.tag.outputs.tags }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

## How It Works

- **PR events**: `VERSION=pr-42`, `TAGS` contains only `registry/image:pr-42`
- **Push to main**: `VERSION=20260314123456_abc1234`, `TAGS` contains two lines:
  `registry/image:20260314123456_abc1234` and `registry/image:latest`
- The `{echo "tags<<EOF" ...}` heredoc block creates a multiline output value in
  `$GITHUB_OUTPUT`, which `docker/build-push-action` accepts as multiple tags
- All `${{ context }}` values are passed through `env:` variables, never interpolated
  directly into the shell script

## Verification

After the workflow runs:
- On a PR: only `pr-N` tag appears in the registry
- On a main merge: both `timestamp_sha` and `latest` tags appear in the registry

## Notes

- The `$'\n'` syntax is POSIX shell for a literal newline in a variable — it works in
  `bash` and `sh` (Alpine's default shell)
- The closing `EOF` delimiter must be on its own line with no leading whitespace
- If you also want a `sha`-only tag, add it to the `TAGS` variable similarly
- This pattern works for any registry (GHCR, Docker Hub, ECR, GCR)

## References

- [GitHub Actions security hardening: using env vars instead of inline interpolation](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-an-intermediate-environment-variable)
- [docker/build-push-action multiline tags](https://github.com/docker/build-push-action)
- [GitHub Actions multiline output syntax](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/passing-information-between-jobs#defining-outputs-for-jobs)
