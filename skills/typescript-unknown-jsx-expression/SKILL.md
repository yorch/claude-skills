---
name: typescript-unknown-jsx-expression
description: |
  Fix TypeScript error "Type 'unknown' is not assignable to type ReactNode" when using
  Record<string, unknown> values directly in JSX && short-circuit expressions. Use when:
  (1) JSX expression {someObj.field && <Component />} fails with TS2322,
  (2) Reading from a JSON or untyped object via bracket notation in JSX conditionals,
  (3) Values typed as unknown appear in JSX even when wrapped in String() or guarded with
  truthiness checks. Fix: use !! to coerce to boolean before the && operator.
author: Claude Code
version: 1.0.0
date: 2026-03-15
---

# TypeScript `unknown` in JSX `&&` Expressions

## Problem

When using `Record<string, unknown>` (or any `unknown`-typed values) in JSX conditional
rendering with `&&`, TypeScript raises:

```
Type 'unknown' is not assignable to type 'string | number | bigint | boolean |
ReactElement<...> | Iterable<ReactNode> | ReactPortal | Promise<...> | null | undefined'
```

Even when the value is wrapped in `String()`, the error still occurs because the
JSX expression itself evaluates to `unknown | JSX.Element`.

## Context / Trigger Conditions

- Object is typed as `Record<string, unknown>` (common with JSON fields from APIs)
- JSX contains: `{obj.field && <Component value={String(obj.field)} />}`
- Error TS2322 on the `&&` line, not inside the Component
- TypeScript strict mode enabled

## Root Cause

In TypeScript, `a && b` returns the type of `a` when `a` is falsy — so `unknown && JSX.Element`
resolves to `unknown | JSX.Element`. TypeScript cannot prove `unknown` is a valid `ReactNode`,
so it rejects the expression.

## Solution

Force a `boolean` result with `!!` before the `&&`:

```tsx
// ❌ FAILS — wd.entry_time is unknown
{wd.entry_time && (
  <DetailField value={String(wd.entry_time)} />
)}

// ✅ WORKS — !!wd.entry_time is boolean
{!!wd.entry_time && (
  <DetailField value={String(wd.entry_time)} />
)}

// Also works with null check
{wd.entry_time != null && (
  <DetailField value={String(wd.entry_time)} />
)}
```

For chained `&&`:

```tsx
// ❌ FAILS — first && returns unknown
{wd.needs_reentry && wd.reentry_date && (
  <DetailField value={String(wd.reentry_date)} />
)}

// ✅ WORKS — both forced to boolean
{!!wd.needs_reentry && !!wd.reentry_date && (
  <DetailField value={String(wd.reentry_date)} />
)}
```

## Verification

```bash
yarn frontend:typecheck  # or tsc --noEmit
# Should produce no TS2322 errors on the affected lines
```

## Notes

- This is not a React issue — it's a TypeScript type-narrowing limitation with `unknown`
- `String(unknown)` returns `string` (which is valid ReactNode), but the issue is the
  JSX expression type before `String()` is applied
- Alternative: cast the whole object with a more specific type at the call site
  `const wd = (r.workDetails ?? {}) as Record<string, string | boolean | undefined>`
  — this eliminates all `!!` guards but reduces type safety
- `!!` is the idiomatic JS/TS way to coerce any value to boolean

## References

- [TypeScript handbook: Type narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html)
- [React TypeScript cheatsheet: JSX expressions](https://react-typescript-cheatsheet.netlify.app/docs/basic/getting-started/basic_type_example/)
