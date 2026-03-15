---
name: rails-auto-assigned-field-validation
description: |
  Fix for Rails models where validates :field, presence: true causes ALL creates to
  fail when the field is set by a before_create callback. Use when: (1) validates
  :number, presence: true is added to a model that uses before_create to auto-assign
  a sequence number, (2) model creates silently fail with "number can't be blank",
  (3) auto-generated fields (number, slug, token) fail presence validation despite
  being set in callbacks. Root cause: before_create runs AFTER validations. Fix:
  change before_create to before_validation on: :create.
author: Claude Code
version: 1.0.0
date: 2026-03-15
---

# Rails Auto-Assigned Field Validation

## Problem

Adding `validates :number, presence: true` to a model that auto-assigns `number`
in a `before_create` callback causes all creates to fail with a validation error
("number can't be blank"), even though the number is being set.

## Context / Trigger Conditions

- Model has a `before_create` that assigns a field (e.g., sequence number, slug, token)
- Adding a `presence: true` validation on that field breaks all creates
- Error: "FieldName can't be blank" on new records
- Existing records are fine; only creates fail
- Common with auto-incrementing record numbers: `self.number = (Model.maximum(:number) || 0) + 1`

## Root Cause

Rails callback execution order:

```
1. before_validation
2. **validates** ← runs HERE
3. before_save
4. before_create   ← field is assigned HERE (too late!)
5. INSERT
6. after_create
7. after_save
```

When `before_create` assigns the field, validations have already run — the field is
still blank when validated.

## Solution

Change `before_create` to `before_validation on: :create`:

```ruby
# ❌ BROKEN — validation runs before the field is assigned
validates :number, :entry_date, presence: true
before_create :assign_number

# ✅ CORRECT — field is assigned before validation
validates :number, :entry_date, presence: true
before_validation :assign_number, on: :create

private

def assign_number
  self.number = (self.class.maximum(:number) || 0) + 1
end
```

The `on: :create` guard ensures the callback only runs on create, not on every
`valid?` call (which could re-assign the number on updates).

## Verification

```ruby
# Should now pass
record = Model.new(required_attrs)
record.valid?   # => true (number is now set before validation)
record.save     # => true
record.number   # => 1 (or next sequence)
```

## Example (this codebase)

`app/models/corrective_maintenance.rb` and `preventive_maintenance.rb` both
auto-assign `number` with `MAX(number) + 1`. When `validates :number, presence: true`
was added, all creates broke until the callback was changed:

```ruby
# app/models/corrective_maintenance.rb
validates :entry_date, :entry_km, :number, presence: true
before_validation :assign_number, on: :create   # was: before_create

private

def assign_number
  self.number = (CorrectiveMaintenance.maximum(:number) || 0) + 1
end
```

## Notes

- This applies to any auto-generated field: slugs, tokens, UUIDs (when generated in Ruby),
  serial numbers, etc.
- The `on: :create` is important — without it, `assign_number` fires on every `save`,
  which would reassign the number on updates and break uniqueness
- ActiveRecord unique index (`UNIQUE` constraint) still provides DB-level protection;
  the presence validation is a Ruby-layer guard for cleaner error messages
- Race condition mitigation: even with `before_validation`, MAX()+1 is still raceable;
  pair with `rescue ActiveRecord::RecordNotUnique` retry logic in mutations/controllers
