# Design: PR Build Support for `gha-docker-publish`

**Date:** 2026-03-15
**Skill:** `gha-docker-publish/SKILL.md`
**Approach:** Option A — extend the existing single workflow file

---

## Summary

Extend the `gha-docker-publish` GitHub Actions workflow pattern to support PR builds.
Every PR triggers a Docker build (validation). If the PR carries the `publish-docker`
label, the image is also pushed to GHCR tagged as `pr-<number>`.

---

## Trigger Changes

Add a `pull_request` trigger with four activity types:

```yaml
pull_request:
  types: [opened, synchronize, reopened, labeled]
```

- `opened` / `reopened` — run on PR creation and re-open
- `synchronize` — run on every new commit pushed to the PR
- `labeled` — run when a label is added, so attaching `publish-docker` to an
  existing PR immediately triggers a build+push

`unlabeled` is excluded — removing the label does not need to trigger a build.

---

## Tag Strategy

Add `type=ref,event=pr` and guard `datetime_sha` with an `enable` condition:

```yaml
tags: |
  type=ref,event=pr
  type=raw,value=${{ steps.commit.outputs.datetime }}_${{ steps.commit.outputs.sha }},enable=${{ github.event_name != 'pull_request' }}
  type=ref,event=branch
  type=raw,value=latest,enable={{is_default_branch}}
```

| Tag | PR | push to main | push to v* tag |
|-----|----|--------------|----------------|
| `pr-42` | ✅ | — | — |
| `datetime_sha` | — | ✅ | ✅ |
| `main` (branch name) | — | ✅ | — |
| `latest` | — | ✅ | — |

`type=ref,event=pr` is built into `docker/metadata-action` and emits `pr-<number>`
automatically. The `enable` guard on `datetime_sha` keeps PR images identified solely
by PR number, without a redundant datetime_sha tag.

---

## Push Expression

Replace the existing `push:` field with a three-way condition:

```yaml
push: >-
  ${{
    github.event_name == 'push' ||
    (github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'publish-docker')) ||
    (github.event_name == 'workflow_dispatch' && inputs.push)
  }}
```

| Event | Pushes? |
|-------|---------|
| `push` to main or `v*` tag | Always |
| `pull_request` without `publish-docker` label | Never (build-only) |
| `pull_request` with `publish-docker` label | Always |
| `workflow_dispatch` with `push: true` | Yes |
| `workflow_dispatch` with `push: false` | No (dry-run) |

`contains(github.event.pull_request.labels.*.name, 'publish-docker')` reads the
label set at run time — so if the label already exists on the PR when a new commit
is pushed, that commit's build also pushes.

---

## Files Changed

- `gha-docker-publish/SKILL.md` — update the complete workflow YAML, add PR tag
  to the tags table, document the push expression logic, update the setup checklist
  to mention the `publish-docker` label

---

## Out of Scope

- Image cleanup on PR close (no GHA workflow for registry deletion)
- Multi-architecture PR builds
- External registry pushes on PRs (only GHCR)
