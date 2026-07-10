# react-app-review

Conducts a thorough, React-specific code review of an existing React or Next.js
application and produces a single `CODE_REVIEW.md` report at the project root.
The goal is simpler logic, smaller components, reusable primitives and hooks, and
a safe incremental refactor roadmap — **not** a stylistic rewrite. Read-only by
default: it proposes changes rather than making them.

## When to use

- Review / audit / refactor a React app, or a React code review
- Find duplicated components, propose shared primitives, or extract custom hooks
- Clean up `useEffect` and state/effect anti-patterns
- Next.js App Router / RSC review

Works with TypeScript or JavaScript and any styling, state, or routing library.

## What it produces

- `CODE_REVIEW.md` — findings tied to specific files (component design, state and
  effects, RSC/Next.js, duplication, accessibility) plus a dependency-aware,
  incremental refactor roadmap. No application code is changed.

## Files

- `SKILL.md` — operating principles, scope rules, and the full review workflow
