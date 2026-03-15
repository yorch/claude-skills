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
automatically — it is only active on `pull_request` events, so no `enable=` guard is
needed on that line.

The `enable=${{ github.event_name != 'pull_request' }}` on the `datetime_sha` line
works via GHA runner pre-interpolation: GHA resolves `${{ }}` expressions to `true`
or `false` before passing the string to the action. This is distinct from
`{{is_default_branch}}` on the `latest` line, which is a `metadata-action` bake
template resolved by the action itself. Both mechanisms work but are not the same
feature.

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

**Behavior change from original expression:** The original `push:` expression was
`github.event_name != 'workflow_dispatch' || inputs.push`, which evaluates `true`
for any trigger type other than `workflow_dispatch` (including a hypothetical
`schedule:` trigger). The new explicit enumeration only pushes on the three named
event types. Any future trigger added to the workflow must be explicitly included
in this expression.

**Fork PR limitation (public repos):** On `pull_request` events from forked
repositories, GHA restricts `GITHUB_TOKEN` to read-only regardless of the
`permissions:` declaration. The `publish-docker` label check will pass but the
GHCR push will fail with a permission error. This is expected GHA behavior. The
feature works as designed only for PRs from branches within the same repository.
Users of public repos should document this restriction for contributors.

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
