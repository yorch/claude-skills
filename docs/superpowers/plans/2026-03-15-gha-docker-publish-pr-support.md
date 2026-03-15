# gha-docker-publish PR Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `gha-docker-publish/SKILL.md` to include PR build support — every PR builds the Docker image for validation, and PRs with the `publish-docker` label also push to GHCR tagged as `pr-<number>`.

**Architecture:** Single-file change to the skill's workflow YAML and surrounding prose. No new files created. Three surgical edits to the workflow YAML (trigger block, metadata-action tags block, push expression), plus updates to the explanatory tables and setup checklist.

**Tech Stack:** GitHub Actions YAML, `docker/metadata-action@v5`, `docker/build-push-action@v6`

**Spec:** `docs/superpowers/specs/2026-03-15-gha-docker-publish-pr-support-design.md`

---

## Chunk 1: Workflow YAML Changes

### Task 1: Add `pull_request` trigger

**Files:**
- Modify: `gha-docker-publish/SKILL.md` — `on:` block

- [ ] **Step 1: Locate the `on:` block**

  Open `gha-docker-publish/SKILL.md`. Find the `on:` block (near the top of the workflow YAML, after the `name:` line). It currently reads:

  ```yaml
  on:
    push:
      branches:
        - main
      tags:
        - "v*"
    workflow_dispatch:
      inputs:
        push:
          description: "Push image to registries"
          required: false
          default: true
          type: boolean
  ```

- [ ] **Step 2: Add the `pull_request` trigger**

  Insert the `pull_request` block between `push` and `workflow_dispatch`:

  ```yaml
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
  ```

- [ ] **Step 3: Verify the diff**

  Confirm only the `pull_request:` block was added. No other lines changed.

- [ ] **Step 4: Commit**

  ```bash
  git add gha-docker-publish/SKILL.md
  git commit -m "feat(gha-docker-publish): add pull_request trigger for PR builds"
  ```

---

### Task 2: Update metadata-action tags block

**Files:**
- Modify: `gha-docker-publish/SKILL.md` — `Extract Docker metadata` step

- [ ] **Step 1: Locate the tags block**

  Find the `Extract Docker metadata` step. The `tags:` block currently reads:

  ```yaml
  tags: |
    type=raw,value=${{ steps.commit.outputs.datetime }}_${{ steps.commit.outputs.sha }}
    type=ref,event=branch
    type=raw,value=latest,enable={{is_default_branch}}
  ```

- [ ] **Step 2: Replace the tags block**

  Replace with:

  ```yaml
  tags: |
    type=ref,event=pr
    type=raw,value=${{ steps.commit.outputs.datetime }}_${{ steps.commit.outputs.sha }},enable=${{ github.event_name != 'pull_request' }}
    type=ref,event=branch
    type=raw,value=latest,enable={{is_default_branch}}
  ```

  Key changes:
  - New first line: `type=ref,event=pr` — emits `pr-42` on PR events only (metadata-action built-in, no `enable=` guard needed)
  - `datetime_sha` line gains `,enable=${{ github.event_name != 'pull_request' }}` — GHA pre-interpolates this to `true`/`false` before the action sees it, suppressing the tag on PR events

- [ ] **Step 3: Verify the diff**

  Confirm exactly two lines changed in this block (new `type=ref,event=pr` line added; `enable=` appended to the `datetime_sha` line).

- [ ] **Step 4: Commit**

  ```bash
  git add gha-docker-publish/SKILL.md
  git commit -m "feat(gha-docker-publish): add pr-N tag, suppress datetime_sha on PRs"
  ```

---

### Task 3: Update the push expression

**Files:**
- Modify: `gha-docker-publish/SKILL.md` — `Build and push` step

- [ ] **Step 1: Locate the push expression**

  Find the `Build and push` step. The `push:` line currently reads:

  ```yaml
  push: ${{ github.event_name != 'workflow_dispatch' || inputs.push }}
  ```

- [ ] **Step 2: Replace the push expression**

  Replace with a three-way explicit condition:

  ```yaml
  push: >-
    ${{
      github.event_name == 'push' ||
      (github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'publish-docker')) ||
      (github.event_name == 'workflow_dispatch' && inputs.push)
    }}
  ```

  The `>-` YAML scalar folds newlines to spaces and strips trailing newline — GHA's expression parser handles the resulting single-line expression correctly.

- [ ] **Step 3: Verify the diff**

  Confirm the `push:` field changed from a one-liner to the multiline block above. No other lines in the step changed.

- [ ] **Step 4: Commit**

  ```bash
  git add gha-docker-publish/SKILL.md
  git commit -m "feat(gha-docker-publish): push only on main/tag/labeled-PR/dispatch"
  ```

---

## Chunk 2: Prose & Documentation Updates

### Task 4: Update the Tags Generated table

**Files:**
- Modify: `gha-docker-publish/SKILL.md` — `### Tags Generated` section

- [ ] **Step 1: Locate the Tags Generated table**

  Find the `### Tags Generated` section under `## Key Design Decisions`. It currently has four rows.

- [ ] **Step 2: Add the PR row and extend column headers**

  Replace the table with:

  ```markdown
  | Tag pattern | Example | When applied |
  |---|---|---|
  | `pr-N` | `pr-42` | PR events only — human-readable, identifies the PR |
  | `datetime_sha` | `202603151430_a1b2c3d` | push and tag events — chronological + traceable |
  | Branch name | `main` | branch push events (not tag push events) — human-readable current ref |
  | `latest` | `latest` | Only on the default branch (`main`) |
  | Tag ref | `v1.2.3` | Only when pushing a `v*` git tag |
  ```

- [ ] **Step 3: Verify**

  Confirm the new `pr-N` row is first and the other rows are unchanged.

- [ ] **Step 4: Commit**

  ```bash
  git add gha-docker-publish/SKILL.md
  git commit -m "docs(gha-docker-publish): update tags table with pr-N row"
  ```

---

### Task 5: Add PR push expression explanation

**Files:**
- Modify: `gha-docker-publish/SKILL.md` — `## Key Design Decisions` section

- [ ] **Step 1: Add a new subsection after the existing `metadata-action` explanation**

  After the `### Why metadata-action for latest instead of shell conditionals?` block, add:

  ```markdown
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
  ```

- [ ] **Step 2: Verify**

  Confirm the new subsection appears after `### Why metadata-action for latest instead of shell conditionals?` and before `### workflow_dispatch dry-run`.

- [ ] **Step 3: Commit**

  ```bash
  git add gha-docker-publish/SKILL.md
  git commit -m "docs(gha-docker-publish): document PR build and publish-docker label behavior"
  ```

---

### Task 6: Update Setup Checklist

**Files:**
- Modify: `gha-docker-publish/SKILL.md` — `## Setup Checklist`

- [ ] **Step 1: Locate the Setup Checklist**

  Find the `## Setup Checklist` section.

- [ ] **Step 2: Add PR label item**

  Add a new checklist item after the Dockerfile item:

  ```markdown
  - [ ] To enable image push on PRs, create a `publish-docker` label in the GitHub
        repository (Settings → Labels) — PRs without this label build but do not push
  ```

- [ ] **Step 3: Verify**

  The checklist should now have 6 items total (was 5).

- [ ] **Step 4: Commit**

  ```bash
  git add gha-docker-publish/SKILL.md
  git commit -m "docs(gha-docker-publish): add publish-docker label to setup checklist"
  ```
