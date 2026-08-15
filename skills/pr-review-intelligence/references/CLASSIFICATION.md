# Classification Reference

Read by the `pr-feedback-analyst` agent on every batch. Kept deliberately small —
this file is re-read once per batch, so every paragraph is paid for N times per run.

Scoring, routing, and the evidence gate are **not** here; they are aggregation
concerns and live in `SCORING.md`, which the analyst never reads.

## Thread outcome

Every thread resolves to exactly one outcome. This is the most consequential
judgment in the pipeline — everything downstream is scored on it.

| Outcome | Meaning | Signals |
| --- | --- | --- |
| `addressed` | Author changed the code in response | `resolved == true`, or `outdated == true`, or last comment by author confirms a change |
| `declined` | Feedback acknowledged but not acted on | Author defers or disputes and neither `resolved` nor `outdated` holds |
| `discussion` | Question answered, no change expected or needed | Thread is interrogative; reviewer accepts the answer |
| `open` | Merged with the thread unresolved and unanswered | No terminal signal of any kind |

**Do not score on `resolved` alone.** Many teams never click resolve. A thread
ending with the author writing *"all the commands now run with git hooks disabled"*
can still carry `resolved: false`. Scoring on that field alone makes a healthy repo
look like it ignores its reviewers.

Language cues for the author-confirms test:

- **Addressed** — "done", "fixed", "good catch", "updated", "moved to…", "removed",
  "added a test for that", "you're right"
- **Declined** — "out of scope", "we can follow up", "working as intended",
  "intentional", "let's handle that separately", "won't fix", "existing behavior"

**Read to the end of the thread before deciding.** A thread where the author says
"out of scope", the reviewer pushes back, and the author then concedes is
`addressed` with `reversal: true` — not `declined`. The first reply is not the
outcome. Misreading this inverts the signal for that pattern and can suppress a
legitimate rule, so when a thread changes direction, weigh the last position, not
the first.

## Comment categories

Use these spellings exactly. Inventing a category breaks aggregation.

| Category | Covers |
| --- | --- |
| `correctness` | Logic errors, wrong conditions, off-by-one, race conditions, unhandled cases |
| `security` | Injection, authz/authn gaps, secret handling, unsafe deserialization, SSRF |
| `error-handling` | Swallowed exceptions, missing failure paths, bad fallbacks, silent failures |
| `api-contract` | Breaking changes, signature/type changes, backward compatibility, migrations |
| `data` | Schema changes, migrations, query correctness, N+1, transaction boundaries |
| `testing` | Missing tests, wrong test location, weak assertions, flaky patterns |
| `performance` | Algorithmic cost, redundant work, caching, bundle/memory impact |
| `architecture` | Layering violations, misplaced logic, coupling, wrong abstraction |
| `convention` | Project-specific idiom: use helper X, follow pattern Y, put files in Z |
| `readability` | Naming, dead code, comment accuracy, control-flow clarity |
| `style` | Formatting, import order, quotes, semicolons |
| `docs` | Changelog, README, docstrings, migration notes |
| `process` | CI config, release steps, PR hygiene, labels |

`convention` is the highest-value category for this skill's purpose. It captures
knowledge that exists only in reviewers' heads — the rules a generic AI reviewer
cannot know and will never infer from the code alone. When a thread could plausibly
be `convention` or something more generic, prefer `convention` and make the
`pattern` field specific.
