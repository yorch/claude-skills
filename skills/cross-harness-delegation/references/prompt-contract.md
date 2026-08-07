# Briefing a delegate

## The constraint that drives everything

**The delegate has zero conversational context.** It has not read this thread.
It does not know what has already been tried, what the user rejected, which
approach was chosen, or what "the bug we discussed" refers to. It cannot ask a
follow-up question — the run is headless and one-shot.

A brief that would be perfectly adequate for an in-process subagent is usually
badly under-specified for a delegate. An in-process subagent inherits the
conversation; a delegate inherits a filesystem and a string.

Under-briefing is the most common cause of a delegation that returns confident
nonsense.

## Required sections

Write these into `prompt.md`. All six, every time.

### 1. Task

Imperative, self-contained, no pronouns pointing outside the brief.

- Bad: "Fix it the way we discussed."
- Bad: "Apply the same pattern to the other files."
- Good: "In `src/auth/session.ts`, replace the manual JWT expiry check in
  `validateSession()` with a call to `isExpired()` from `src/auth/clock.ts`."

### 2. Context

What the delegate cannot discover cheaply, and what would waste its time.

- The relevant file paths (it will otherwise burn turns searching)
- What has already been attempted and ruled out, with the reason
- Project conventions it must follow that are not obvious from the code
- Which build/test command to use

### 3. Acceptance criteria

Verifiable, mechanical, checkable by running something.

- Good: "`npm test` passes with no new failures."
- Good: "`rg 'jwt.verify' src/` returns no matches."
- Bad: "The code is clean and maintainable."

### 4. Constraints

State these explicitly — defaults differ per harness and are frequently wrong.

- Whether to commit (say it either way; `aider` auto-commits unless stopped)
- Do not modify lockfiles or install dependencies
- Do not touch paths outside the named set
- Do not reformat unrelated code
- Do not upgrade dependencies

### 5. Output format

Exactly what to emit as the final message. Be specific — this is what lands in
`result.txt`.

> Finish with a summary in this form:
> ```
> CHANGED: <file> - <one line why>
> TESTS: <command run> - <pass|fail>
> UNRESOLVED: <anything you could not do, or NONE>
> ```

For `codex` specifically, `--output-schema <FILE>` can *enforce* a JSON shape on
the final message. It is the only harness that can guarantee rather than request
a result format — worth choosing for that reason alone when structured output
matters.

### 6. Honesty clause

Include verbatim, or close to it:

> If you cannot complete this task, say so explicitly and explain what blocked
> you. Do not report success you did not achieve. Do not describe changes you
> did not make. An honest partial result is more useful than a confident
> incorrect one.

This does not make the delegate honest. It measurably reduces confabulated
completions, and it costs one sentence. Verification still happens regardless.

## Review-mode briefs

Reviews need one extra thing: **tell the delegate what evidence to cite.**

> For each finding, give the exact `path:line`, quote the offending line, and
> state the concrete failure it causes. If you cannot point at a specific line,
> do not report the finding.

This is not for the delegate's benefit. It is so the citations can be
mechanically checked against the real files afterwards — a finding with no
`path:line` cannot be verified and must be discarded.

## Template

```markdown
# Task
<imperative, self-contained>

# Context
- Relevant paths: <...>
- Already tried and ruled out: <...>
- Build/test command: <...>

# Acceptance criteria
- <verifiable>
- <verifiable>

# Constraints
- Do NOT commit.
- Do NOT modify lockfiles or install dependencies.
- Do NOT touch files outside: <paths>

# Output format
Finish with:
CHANGED: <file> - <why>
TESTS: <command> - <pass|fail>
UNRESOLVED: <blockers, or NONE>

# Honesty
If you cannot complete this task, say so explicitly and explain what blocked
you. Do not report success you did not achieve.
```
