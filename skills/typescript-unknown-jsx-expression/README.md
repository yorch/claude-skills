# typescript-unknown-jsx-expression

Fixes the TypeScript error `Type 'unknown' is not assignable to type 'ReactNode'`
that appears when an `unknown`-typed value (commonly from a
`Record<string, unknown>` JSON field) is used in a JSX `&&` short-circuit. Because
`a && b` evaluates to the type of `a` when `a` is falsy, `unknown && <JSX />`
resolves to `unknown | JSX.Element`, which TypeScript rejects as a `ReactNode` —
even when the value is wrapped in `String()`.

## When to use

- `{obj.field && <Component />}` fails with TS2322 on the `&&` line (not inside
  the component)
- Reading from a JSON or untyped object via bracket notation in a JSX conditional
- `unknown` values appear in JSX under strict mode despite `String()` or guards

## What it fixes

- Coerce the left operand to `boolean` with `!!` (or an explicit `!= null` check)
  before `&&`, so the expression is a valid `ReactNode`. Covers chained `&&` too.

## Files

- `SKILL.md` — problem, root cause, and the `!!` / null-check solution
