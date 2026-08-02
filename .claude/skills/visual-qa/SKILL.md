---
name: visual-qa
description: Use the running app in a headless browser, take desktop and mobile screenshots, and judge whether the layout is state of the art. Use before opening a PR that touches the UI, or on request.
---

# Visual QA workflow

Tests passing is not enough. This workflow means actually using the app and looking at it.

## 1. Run the app

Start the app locally (dev server with a seeded test database). Use a headless browser you can screenshot with (the project's e2e tooling, or Playwright/chrome headless as fallback).

## 2. Use it like a user

Walk through the affected flows for real: click, type, upload, drag. Do not just load pages. Note anything that feels broken, slow, or awkward while doing it.

## 3. Screenshots, always both viewports

For every affected screen and state (empty, filled, error, loading):

- Desktop: 1440x900
- Mobile: 390x844

Save screenshots to the scratchpad and actually look at each one with the Read tool.

## 4. Judge

Assess each screenshot against these questions:

- Is the layout state of the art? Spacing, typography, hierarchy, alignment.
- Does it honor the project's values: minimal, radically space-optimized, especially on mobile, no clutter?
- Mobile specifically: touch targets, no horizontal overflow, readable without zooming, drag and drop usable.
- Are desktop and mobile consistent with each other?

Be a harsh critic. "Works" is not the bar; "would a good designer ship this" is.

## 5. Fix or report

Fix clear defects immediately and re-screenshot to confirm. For subjective judgment calls, present the screenshots and your assessment to the user with a recommendation.
