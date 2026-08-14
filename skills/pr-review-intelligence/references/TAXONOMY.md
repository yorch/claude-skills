# Taxonomy and Scoring

How a corpus of review threads becomes a ranked set of rules. This is the
analytical core of the skill: classification, outcome inference, scoring, and the
gates that keep invented advice out of the output.

## Contents

- [Thread outcome](#thread-outcome)
- [Comment categories](#comment-categories)
- [Signal scoring](#signal-scoring)
- [Routing a finding](#routing-a-finding)
- [The evidence gate](#the-evidence-gate)
- [Deriving do-not-flag](#deriving-do-not-flag)
- [Rule quality bar](#rule-quality-bar)

## Thread outcome

Every thread resolves to exactly one outcome. This is the most consequential
judgment in the pipeline — scoring depends on it entirely.

| Outcome | Meaning | Signals |
| --- | --- | --- |
| `addressed` | Author changed the code in response | `resolved == true`, or `outdated == true`, or last comment by author confirms a change |
| `declined` | Feedback acknowledged but not acted on | Author defers or disputes and neither `resolved` nor `outdated` holds |
| `discussion` | Question answered, no change expected or needed | Thread is interrogative; reviewer accepts the answer |
| `open` | Merged with the thread unresolved and unanswered | No terminal signal of any kind |

**Do not score on `resolved` alone.** Many teams never click resolve. A thread
ending with the author writing *"all the commands now run with git hooks disabled"*
can still carry `resolved: false`. Scoring on that field alone makes a healthy repo
look like it ignores its reviewers, and suppresses exactly the rules worth keeping.

Language cues for the author-confirms test:

- **Addressed** — "done", "fixed", "good catch", "updated", "moved to…", "removed",
  "added a test for that", "you're right"
- **Declined** — "out of scope", "we can follow up", "working as intended",
  "intentional", "let's handle that separately", "won't fix", "existing behavior"

A declined thread where the **reviewer then pushed back and the author conceded**
is `addressed`, not `declined`. Read to the end of the thread; the first reply is
not the outcome. These reversal threads are the single most valuable pattern in the
corpus — see [Deriving do-not-flag](#deriving-do-not-flag).

## Comment categories

Adapted from published code-review taxonomies, collapsed to categories that are
distinguishable from a thread alone and that route differently downstream.

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
cannot possibly know and will never infer from the code alone. Weight it accordingly.

## Signal scoring

Each candidate rule gets a score from three factors:

```text
score = frequency × adherence × severity_weight
```

**frequency** — distinct PRs where a thread of this pattern appeared. Count PRs, not
threads: one reviewer commenting on the same thing across fifteen lines of a single
PR is one observation, not fifteen.

**adherence** — `addressed / (addressed + declined)` for that pattern. This is the
team's own revealed judgment. A pattern raised nine times and declined eight times is
not a rule, no matter how frequent.

**severity_weight** — from category:

| Weight | Categories |
| --- | --- |
| 1.0 | `security`, `correctness`, `error-handling`, `data` |
| 0.8 | `api-contract`, `testing`, `architecture` |
| 0.6 | `convention`, `performance` |
| 0.3 | `readability`, `docs` |
| 0.1 | `style`, `process` |

The weights encode a finding replicated across the code-review literature:
readability, bug, and maintainability comments are resolved at much higher rates
than design-level ones, and style comments are both the most frequent and the least
valuable. Without severity weighting, a mined ruleset degenerates into a list of
naming nits, because those are what reviewers type most often.

Report the three factors alongside every rule. A rule with `frequency: 12,
adherence: 0.42` is a live disagreement inside the team, not a settled rule, and the
report should say so rather than silently ranking it.

## Routing a finding

Not every real pattern belongs in `review-guidelines.md`.

```text
                    ┌─ adherence < 0.5 ──────────────→ do-not-flag.md
                    │
observation ────────┼─ category ∈ {style, process} ──→ recommend a linter/CI rule
                    │
                    ├─ mechanically checkable ───────→ recommend a lint rule,
                    │  (formatting, import order)      then a review rule as backup
                    │
                    └─ everything else ──────────────→ review-guidelines.md
                                                       + patterns/<area>.md if it
                                                         has a Wrong/Correct pair
```

**Prefer a linter over a review rule wherever one can do the job.** A repo whose
reviewers repeatedly ask for import ordering does not need an AI reviewer trained to
nag about import ordering — it needs a lint rule, and the report should say so in
`feedback-loop-report.md`. Every check that moves from review to tooling is one that
stops costing a round trip.

## The evidence gate

**A rule requires ≥2 citing PRs from distinct threads, or it is dropped.**

This is the primary defense against the failure mode of this whole skill: producing
plausible, generic advice ("handle errors properly", "write tests") that reads like
mined insight but was actually invented. One thread is an anecdote. A rule that
cannot cite two independent occurrences did not come from the corpus.

Enforce it mechanically at aggregation, not by asking the model to be careful. When
a compelling single-occurrence observation is dropped, list it in a
`Single-occurrence observations` appendix rather than deleting it — it is a
hypothesis for the next run, when a larger corpus may confirm it.

Every rule carries its citations as `owner/repo#1234` links. A rule whose citations
do not actually contain the claimed feedback is worse than no rule.

## Deriving do-not-flag

`do-not-flag.md` is what separates a useful mined ruleset from more noise. Roughly a
quarter of automated review comments are rejected by developers as out-of-scope or
wrong; suppressing those categories is the highest-leverage output this skill
produces.

Three sources, in descending value:

1. **Declined human threads.** A reviewer raised it, the author said "out of scope"
   or "intentional", and it was merged anyway. Record the pattern *and the stated
   reason* — the reason is what lets a future reviewer distinguish the legitimate
   exception from a genuine instance.

2. **Bot threads that were declined or ignored.** Direct evidence of what this team
   considers noise, already labelled by an automated reviewer. If a bot flagged
   something eight times and it was never once addressed, that is a suppression rule
   with unusually strong evidence.

3. **Reversal threads.** Reviewer raised → author pushed back → reviewer conceded.
   These define the *boundary* of a rule. They belong in `review-guidelines.md` as an
   explicit exception clause on the related rule, not as a standalone suppression.

Apply a suppression threshold: **3 or more declines of the same pattern** with no
offsetting addressed instances. Below that, note it as weak evidence rather than
asserting a suppression rule.

## Rule quality bar

A rule that survives every gate above must still be **checkable by a reviewer that
sees a diff and can read the repo**. Reject rules that need runtime behavior,
production metrics, or product context.

| Reject | Rewrite as |
| --- | --- |
| "Make sure the code is performant" | "Flag `.map()` chains over query results in `app/services/` — the team asks for a single query instead (#812, #904)" |
| "Follow team conventions" | "New API handlers must go under `src/api/handlers/`; flag handlers defined inline in route files (#455, #501)" |
| "Handle errors properly" | "`rescue` blocks that neither re-raise nor log are flagged; the team requires one or the other (#233, #278, #341)" |

Each rule in the output needs five fields:

- **Rule** — imperative, specific, one sentence
- **Where** — path globs it applies to, so the reviewer can scope it
- **Detect** — what to look for in a diff, concretely enough to act on
- **Why** — the team's stated reasoning, quoted from a real thread where possible
- **Evidence** — citing PR links, plus frequency / adherence / severity

The **Where** field is what makes the output routable. Rules grouped by path glob
let a reviewer load only the patterns relevant to the files in front of it, instead
of carrying the whole ruleset on every review.
