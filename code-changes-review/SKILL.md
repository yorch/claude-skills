---
name: code-changes-review
description: >
  Perform a comprehensive code review of current uncommitted changes in a git
  repository. Analyzes for bugs, security vulnerabilities, best practices, DRY
  violations, code smells, performance issues, and areas of improvement. Use
  when: review changes, code review, check my code, review diff, pre-commit
  review, PR review, quality check. Works with any language or framework.
---

# Code Changes Review

Perform a thorough, professional code review of uncommitted changes in the current git working copy.

## Overview

This skill analyzes all staged and unstaged changes, providing actionable feedback across multiple quality dimensions:

- **Correctness** - Logic errors, bugs, edge cases
- **Security** - Vulnerabilities, injection risks, sensitive data exposure
- **Best Practices** - Language idioms, framework conventions, patterns
- **DRY/Reusability** - Code duplication, abstraction opportunities
- **Code Smells** - Maintainability issues, complexity, coupling
- **Performance** - Inefficiencies, N+1 queries, memory leaks
- **Testing** - Test coverage gaps, test quality

## Instructions

### Step 1: Gather Changes

First, collect all changes to be reviewed:

```bash
# Check repository status
git status

# Get the full diff of all changes (staged + unstaged)
git diff HEAD

# If only staged changes should be reviewed
git diff --cached
```

**Important**: Review BOTH staged and unstaged changes unless the user specifically requests otherwise.

### Step 2: Understand Context

Before reviewing changes, understand the broader context:

1. **Identify the purpose** - What is the change trying to accomplish?
2. **Check related files** - Read unchanged files that interact with modified code
3. **Understand the codebase patterns** - Look at existing code style and conventions
4. **Review recent commits** - Check `git log -5 --oneline` for context

### Step 3: Analyze Each Change

For each modified file, evaluate against the [Review Checklist](CHECKLIST.md):

#### 3.1 Correctness & Logic

- [ ] Does the code do what it's supposed to do?
- [ ] Are edge cases handled (null, empty, boundary values)?
- [ ] Are error conditions properly handled?
- [ ] Is the control flow correct (loops, conditionals)?
- [ ] Are there off-by-one errors?
- [ ] Are race conditions possible in concurrent code?

#### 3.2 Security

- [ ] Input validation present for user data?
- [ ] SQL/NoSQL injection prevention (parameterized queries)?
- [ ] XSS prevention (output encoding)?
- [ ] Command injection prevention?
- [ ] Sensitive data not logged or exposed?
- [ ] Authentication/authorization properly enforced?
- [ ] Secrets not hardcoded?
- [ ] Dependencies up-to-date and without known vulnerabilities?

#### 3.3 Best Practices

- [ ] Follows language/framework idioms?
- [ ] Consistent naming conventions?
- [ ] Appropriate abstraction level?
- [ ] Single Responsibility Principle followed?
- [ ] Functions/methods reasonably sized?
- [ ] Comments explain "why", not "what"?
- [ ] Error messages helpful and not exposing internals?

#### 3.4 DRY & Reusability

- [ ] No duplicated code within the change?
- [ ] No duplication with existing codebase?
- [ ] Opportunities to extract reusable functions/components?
- [ ] Consistent patterns with existing code?

#### 3.5 Code Smells

- [ ] No magic numbers/strings (use constants)?
- [ ] No deeply nested code (max 3 levels)?
- [ ] No overly long functions (context-dependent, usually <50 lines)?
- [ ] No God objects/functions doing too much?
- [ ] No tight coupling between components?
- [ ] No dead code or commented-out code?

#### 3.6 Performance

- [ ] No N+1 query patterns?
- [ ] Appropriate data structures used?
- [ ] No unnecessary iterations or computations?
- [ ] Resources properly closed/disposed?
- [ ] Caching considered where appropriate?
- [ ] No memory leaks (especially in long-running processes)?

#### 3.7 Testing

- [ ] Are new features covered by tests?
- [ ] Are edge cases tested?
- [ ] Do tests follow AAA pattern (Arrange, Act, Assert)?
- [ ] Are tests independent and deterministic?
- [ ] Is test naming clear and descriptive?

### Step 4: Provide Structured Feedback

Organize findings by severity and category:

```markdown
## Code Review Summary

**Scope**: [X files changed, Y insertions, Z deletions]
**Overall Assessment**: [Brief summary]

---

### Critical Issues (Must Fix)

These issues must be resolved before merging:

1. **[SECURITY]** `path/to/file.js:42` - SQL injection vulnerability
   - **Problem**: User input directly interpolated into query
   - **Fix**: Use parameterized query with `db.query(sql, [param])`

2. **[BUG]** `path/to/file.py:87` - Off-by-one error in loop
   - **Problem**: Loop iterates one extra time causing IndexError
   - **Fix**: Change `range(len(items) + 1)` to `range(len(items))`

---

### Important Issues (Should Fix)

These issues should be addressed:

1. **[PERFORMANCE]** `path/to/file.ts:23` - N+1 query in loop
   - **Problem**: Database query inside forEach loop
   - **Suggestion**: Batch fetch with single query using `IN` clause

---

### Suggestions (Nice to Have)

These are recommendations for improvement:

1. **[DRY]** `path/to/utils.js:15-30` - Duplicated validation logic
   - **Current**: Same email regex in 3 places
   - **Suggestion**: Extract to shared `validateEmail()` function

---

### Positive Observations

Good practices noticed in this change:

- Proper error handling with specific error types
- Clear function naming following conventions
- Comprehensive input validation on API endpoints
```

### Step 5: Provide Actionable Recommendations

For each issue:

1. **Be specific** - Include file path and line numbers
2. **Explain why** - Not just what's wrong, but the impact
3. **Show how to fix** - Provide concrete code suggestions when possible
4. **Prioritize** - Critical > Important > Suggestions

### Step 6: Summary and Next Steps

End with:

1. **Overall quality assessment** (Ready to merge / Needs work / Major revision needed)
2. **Priority items** - Top 3 things to fix first
3. **Follow-up questions** - Clarifications needed from the author

## Severity Levels

| Level       | Label           | Description                                  | Action                |
| ----------- | --------------- | -------------------------------------------- | --------------------- |
| Critical    | `[CRITICAL]`    | Security vulnerabilities, data loss, crashes | Must fix before merge |
| Bug         | `[BUG]`         | Incorrect behavior, logic errors             | Must fix              |
| Security    | `[SECURITY]`    | Potential security issues                    | Must fix              |
| Performance | `[PERFORMANCE]` | Significant performance impact               | Should fix            |
| Warning     | `[WARNING]`     | Code smells, potential issues                | Should fix            |
| DRY         | `[DRY]`         | Duplication, reusability                     | Consider fixing       |
| Style       | `[STYLE]`       | Conventions, formatting                      | Nice to have          |
| Suggestion  | `[SUGGESTION]`  | Improvements, alternatives                   | Nice to have          |
| Positive    | `[POSITIVE]`    | Good practices observed                      | Acknowledgment        |

## Language-Specific Considerations

### JavaScript/TypeScript

- Check for `===` vs `==`
- Proper async/await error handling
- Memory leaks in event listeners
- Type safety (TypeScript)
- Module import/export patterns

### Python

- Type hints usage
- Context managers for resources
- List comprehension vs loops
- Exception handling specificity
- PEP 8 compliance

### Go

- Error handling (not ignoring errors)
- Goroutine leaks
- Proper defer usage
- Interface segregation
- Effective Go patterns

### Rust

- Ownership and borrowing
- Error handling with Result/Option
- Unsafe code justification
- Clippy warnings
- Idiomatic patterns

### SQL Changes

- Injection vulnerabilities
- Index usage
- N+1 patterns
- Transaction boundaries
- Migration reversibility

## Review Modes

### Quick Review (Default)

Focus on critical and important issues:

- Security vulnerabilities
- Obvious bugs
- Major code smells

### Thorough Review (`--thorough`)

Complete analysis including:

- All checklist items
- Style consistency
- Documentation quality
- Test coverage analysis

### Security-Focused Review (`--security`)

Deep dive into security:

- OWASP Top 10 checks
- Authentication/authorization
- Data validation
- Cryptographic practices

### Performance Review (`--performance`)

Focus on efficiency:

- Algorithm complexity
- Database query patterns
- Memory usage
- Caching opportunities

## Integration with CI/CD

For automated reviews, output can be formatted as:

```bash
# JSON format for CI integration
--format json

# GitHub-compatible annotations
--format github

# GitLab-compatible notes
--format gitlab
```

## Examples

### Example 1: Simple Review Request

**User**: Review my changes

**Response**: [Full review following the structure above]

### Example 2: Focused Review

**User**: Review my changes focusing on security

**Response**: [Security-focused review with OWASP considerations]

### Example 3: Pre-commit Review

**User**: Quick review before I commit

**Response**: [Quick review highlighting only critical/important issues]

## Additional Resources

- [CHECKLIST.md](CHECKLIST.md) - Complete review checklist with examples
- [OWASP Top 10](https://owasp.org/www-project-top-ten/) - Security reference
- [Code Smells Catalog](https://refactoring.guru/refactoring/smells) - Refactoring patterns

## Best Practices for Reviewers

1. **Be constructive** - Focus on the code, not the person
2. **Explain the "why"** - Help the author learn
3. **Offer alternatives** - Don't just criticize
4. **Acknowledge good work** - Positive feedback matters
5. **Ask questions** - Understand before judging
6. **Be timely** - Quick feedback is valuable feedback
7. **Stay focused** - Review what changed, not unrelated code
