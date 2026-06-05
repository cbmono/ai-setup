---
name: test-locators
description: Use when building or editing frontend UI — components, pages, forms, buttons, links, inputs, modals, or any interactive/asserted element. Adds stable test locators (data-testid / data-test) and accessibility handles so E2E tests don't go flaky.
---

# Stable test locators for frontend

When you create or modify user-facing UI, add a stable test locator to every element a test or user would interact with or assert on — buttons, links, inputs, selects, checkboxes, form containers, list items, modals, toasts, and anything with dynamic state. These become the handles QA uses in automation; without them E2E tests latch onto CSS classes, DOM position, or text and break on the next refactor.

## What to add

- **A test attribute:** `data-testid`, or `data-test` if that's already the project's convention. Match what existing components use — grep a few siblings first; never mix both in one codebase.
- **Where they fit naturally, semantic/accessibility handles too:** `label`, `aria-label`, `name`, `id`, `role`. These serve screen readers and double as stable locators.

## Naming

Format: `<feature-or-section>-<element>-<purpose>`, lowercase `kebab-case`, by **business meaning**.

- Good: `login-submit-button`, `registration-country-card-de`, `checkout-payment-submit-button`, `user-profile-save-button`, `disclosure-legal-documents-checkbox`
- Bad: `button1`, `test`, `blue-button`, `right-panel-button`, `country-card-0`, `checkbox-1`

**Avoid encoding** position/index (`-0`, `-1`), color, CSS class, component-library names, or random numbers — they break when layout, styling, or order changes. Prefer a stable business identifier: `country-card-de`, not `country-card-0`.

## When to skip

Purely decorative, static, non-asserted elements (spacers, presentational wrappers, icons) don't need a locator. Don't blanket every `<div>` — aim for the elements a test would realistically target.
