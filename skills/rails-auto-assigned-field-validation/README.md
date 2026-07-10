# rails-auto-assigned-field-validation

Fixes a Rails ordering bug where adding `validates :field, presence: true` to a
model that auto-assigns that field in a `before_create` callback makes **every**
create fail with "field can't be blank". The cause is callback order:
`before_create` runs *after* validations, so the field is still blank when
validated.

## When to use

- A `presence: true` validation was added to a field set by a `before_create`
  callback (sequence number, slug, token) and now all creates fail
- Model creates fail with "FieldName can't be blank" while existing records are fine
- Auto-incrementing record numbers break on create

## What it fixes

- Moves the assignment to `before_validation on: :create` so the field is set
  before validations run — and explains why the `on: :create` guard matters.

## Files

- `SKILL.md` — problem, callback-order root cause, fix, and verification
