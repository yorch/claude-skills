---
name: react-app-review
description: >
  Conduct a thorough, React-specific code review of an existing React or
  Next.js application. Identifies opportunities to simplify components,
  extract reusable primitives and hooks, fix state/effect anti-patterns,
  improve accessibility, and propose a safe, incremental refactor roadmap
  without changing user-facing behavior. Produces a single CODE_REVIEW.md
  report. Use when: review my React app, audit React code, refactor React,
  React code review, find duplicated components, propose shared components,
  extract custom hooks, clean up useEffect, improve React structure,
  Next.js review, App Router review, RSC review. Works with TypeScript or
  JavaScript, any styling/state library.
---

# React Code Review

Produce a single `CODE_REVIEW.md` report at the project root that proposes safe, incremental refactors for an existing React/Next.js application. The goal is **simpler logic, smaller components, reusable primitives, and a working roadmap** — not a stylistic rewrite.

## Operating principles

- **Read-only by default.** Do not edit application code. The deliverable is the report. Only edit code if the user explicitly asks for it after reviewing the report.
- **Preserve behavior.** Routing, public APIs, network contracts, and visible UX stay the same unless the user flagged something as broken.
- **Match existing conventions.** TypeScript vs JavaScript, styling approach (Tailwind, CSS modules, styled-components, vanilla-extract), state libraries (Redux, Zustand, Jotai, Context, TanStack Query, SWR), router (React Router, TanStack Router, Next.js App/Pages Router), and test setup are inputs, not targets to change. Only propose swapping them out if they are the actual cause of a problem.
- **Earn every recommendation.** Each finding must point to specific files. Vague advice ("consider better separation of concerns") is noise — cut it.
- **No speculative performance work.** Don't suggest `React.memo`, `useMemo`, or `useCallback` unless there is a measurable problem (visible jank, profiler data, large list, expensive compute in a hot path). They add complexity and obscure re-render bugs when applied prophylactically.

## Scope

By default, review the whole working tree of the React app in the current directory. If the user asks to review a specific subset (a PR, a branch diff, a single feature folder), narrow the scope and say so in the report's Executive Summary.

Skip generated and vendor code: `node_modules/`, `.next/`, `dist/`, `build/`, `out/`, `coverage/`, `.turbo/`, anything matched by `.gitignore`.

## Workflow

### Phase 1 — Discover the project (read-only)

1. **Detect the stack.** Read `package.json` to identify React version, framework (Next.js / Remix / Vite / CRA), language (TS/JS), styling, state, data fetching, router, and test runner. Note the package manager from the lockfile (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`).
2. **Map the structure.** Identify entry points, routing layout, global providers, the data-fetching layer, and the top-level component hierarchy. For Next.js App Router, note where Server Components vs Client Components live (`"use client"` directive).
3. **Establish a baseline.** Run the project's lint, typecheck, and test commands using the detected package manager (e.g. `pnpm lint`, `bun run typecheck`). Capture pass/fail and current warning count. If commands aren't defined, note that and move on — don't invent scripts.
4. **Find the heavy files.** List the 20 largest files by line count under the source directory. These are the highest-leverage refactor candidates and the place to start Phase 2.

### Phase 2 — Analyze

Walk the codebase looking for the patterns below. For each finding, capture: file paths, a one-line description, why it matters, and a concrete proposal. Skip categories that don't apply.

#### Component design

- Components over ~200 lines, or doing more than one clear thing (data fetching + business logic + presentation in one file).
- Repeated JSX patterns across files: cards, list items, form fields, modals, dialogs, empty states, loading skeletons, error states. These are extraction candidates.
- Prop drilling more than 2 levels deep. Consider a Context, a colocated provider, or a state library already in use.
- Components that take 8+ props, especially several booleans — usually a sign of merged responsibilities.

#### State and effects

- `useEffect` doing work that belongs in an event handler (fire-and-forget on click), or syncing state that could be derived directly from props/state.
- State that mirrors a prop or is computed from other state — replace with derived values, optionally memoized when the computation is expensive.
- Multiple `useState` calls that always change together — collapse to one object or a `useReducer`.
- Missing or incorrect dependency arrays. Stale closures over props/state.
- Data fetching inside `useEffect` when the project already has TanStack Query / SWR / RTK Query / a Next.js data layer. Migrate to the existing pattern instead of adding a new one.
- Subscriptions, intervals, or event listeners without cleanup.

#### React Server Components and Next.js (when applicable)

- Components marked `"use client"` that don't actually need client features (no state, no effects, no event handlers, no browser APIs). Removing the directive moves them to the server and shrinks the client bundle.
- Heavy client components that could be split: keep an interactive shell as a Client Component, move pure rendering to a Server Component child passed via `children` or props.
- Data fetched in Client Components via `useEffect` when it could happen on the server in a Server Component or Route Handler.
- Use of `next/image`, `next/font`, `next/link` — flag native `<img>`, raw `<a>` for internal links, and unoptimized fonts.
- Server-only secrets read in modules that end up bundled to the client. Confirm via `"server-only"` / `"client-only"` boundaries where helpful.

#### Logic and duplication

- Duplicated utilities: formatters (date, money, number), validators, API clients, fetch wrappers, debounced handlers.
- Inline magic numbers and strings (status codes, route paths, query keys, feature flags) that belong in a constants module or a typed enum.
- Tangled conditional JSX — early returns, extracted subcomponents, or a small lookup map usually beat deeply nested ternaries.
- Type definitions duplicated across files (especially DTOs and form shapes). Consolidate in a `types/` module or colocate with the schema.

#### Structure and naming

- Files in the wrong directory relative to the project's own conventions (a route component living in `components/`, a hook outside `hooks/`).
- Circular imports or tangled module graphs.
- Barrel files (`index.ts`) that re-export everything — flag them when they hurt tree-shaking, cause circular imports, or hide where things actually live.
- Inconsistent naming for the same concept (`getUser`, `fetchUser`, `loadUser`).

#### Accessibility

- Interactive elements built on `<div>` / `<span>` instead of `<button>`, `<a>`, native form controls.
- Form inputs without associated `<label>` (or `aria-label` / `aria-labelledby`).
- Missing `alt` text on `<img>`, missing accessible names on icon-only buttons.
- Custom modals/menus without focus trapping, escape-to-close, or `aria-*` roles.
- Color used as the sole signal for state (errors, required fields).

#### Performance (only when a real problem exists)

- Lists rendered without stable keys, or with `index` as key when items reorder.
- Context providers wrapping a large tree where the value changes on every render — consumers re-render unnecessarily. Splitting the context or memoizing the value usually fixes it.
- Expensive computations in render in a confirmed hot path (a chart, a virtualized table). Memoize and explain why.
- Large dependencies imported at the top of route components when they could be lazy-loaded (`React.lazy`, `next/dynamic`).

#### Testing

- Public-API code without any tests (especially custom hooks and shared components).
- Tests asserting on implementation details (component internal state, class names) instead of user-visible behavior — fragile and discourage refactors.
- Missing tests for the bug-prone areas you're proposing to refactor. Adding a test before a refactor is part of making it safe.

## Phase 3 — Write the report

Write a single markdown file at `<repo-root>/CODE_REVIEW.md` with these sections, in this order. Skip a section entirely if it has nothing useful to say (and note the skip in the Executive Summary).

### 1. Executive summary

3–5 sentences. Cover overall code health, the 2–3 biggest wins available, the rough total effort, and any scope notes (e.g. "reviewed only `apps/web/src/features/checkout`").

### 2. Baseline

What you ran and what came back. One short table:

| Check     | Command          | Result                 |
| --------- | ---------------- | ---------------------- |
| Lint      | `pnpm lint`      | 0 errors, 14 warnings  |
| Typecheck | `pnpm typecheck` | passes                 |
| Tests     | `pnpm test`      | 142 passing, 3 skipped |

If a check wasn't available, write "not configured" — don't invent a script.

### 3. Findings

A table ranked by impact. Keep one row per distinct issue. Group multiple files into the Files cell rather than repeating the row.

| #   | Area | Issue | Impact | Effort | Files |
| --- | ---- | ----- | ------ | ------ | ----- |

- **Impact**: High / Medium / Low
- **Effort**: S (<1h) / M (half day) / L (1+ day)

### 4. Proposed reusable components

For each component you recommend extracting:

- **Name and location** (e.g. `src/components/ui/EmptyState.tsx`)
- **Props API** — full TypeScript signature
- **Consumers** — which existing files would adopt it and what they'd remove
- **Sketch** — minimal implementation, just enough to be obviously correct

### 5. Proposed custom hooks

Same format as components. Focus on hooks that retire duplicated effect/state patterns: `useDebouncedValue`, `useLocalStorage`, `usePagination`, `useDisclosure`, `useFormField`, `useMediaQuery`. Don't propose a hook unless it has at least 2 real consumers in the codebase.

### 6. Directory restructure (only if warranted)

Before → after tree, with one-line justifications per move. If the current structure is fine, write a single sentence saying so and skip the rest. Resist the urge to invent a "better" layout for its own sake.

### 7. Refactor roadmap

An ordered, dependency-aware sequence. Every step must be **independently shippable** and leave the app in a green state (lint, types, tests). Format each step as:

> **Step N — Title** _(Effort: S/M/L)_
>
> - **Goal:** one sentence
> - **Touches:** files or directories
> - **Depends on:** previous step number(s), or "none"
> - **Verify:** the specific commands and/or manual checks that prove it works
> - **Rollback:** what to revert if it goes wrong

Order steps so the lowest-risk, highest-leverage extractions land first (usually shared primitives and pure utilities), and architectural moves (directory restructures, state library swaps) come last.

### 8. Open questions

Anything the review couldn't resolve from the code alone — product decisions, intentional duplication, deprecated paths waiting on a migration. Frame each as a concrete question the team can answer.

## Output

Before starting Phase 2, confirm the delivery format with the user. Offer three options and pick a sensible default based on scope:

- **File** — write `<repo-root>/CODE_REVIEW.md` only. Default for full-app audits and anything the user will likely share, revisit, or work through over multiple sessions.
- **Inline** — present the report directly in the chat, no file written. Default for narrow scopes (single component, small feature folder, quick sanity check) and for ephemeral reviews the user just wants to read once.
- **Both** — write the file and also surface a condensed summary inline. Default when the user explicitly says "show me" or "walk me through" alongside an audit request.

If the user already said how they want it, skip the ask. If they didn't, ask once with the recommended default, then proceed. Don't re-ask on subsequent phases.

Whichever format you produce, end with a one-paragraph wrap-up: where the report lives (or "above"), and the top 3 recommended next steps. Don't create supplementary files unless the user asks.
