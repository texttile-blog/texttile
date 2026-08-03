---
name: feature
description: Build a substantial new feature end to end - worktree, TDD, implementation, visual QA, PR, and review. Use when the user asks to build or implement a feature.
---

# Feature workflow

Follow these steps in order. Do not skip the review at the end.

## 1. Scope

Run `make idea` first to pull the current product notes from the vault. Then restate the feature in one or two sentences and list the acceptance criteria you derive from `idea.md`, its linked notes in `idea/`, and the user's request. If the scope is genuinely ambiguous, ask before writing code.

## 2. Worktree and branch

Create a git worktree with an English branch name:

```
git worktree add ../texttile-<slug> -b feature/<slug>
```

All work happens inside that worktree. Small fixes (per AGENTS.md) may skip the worktree, but anything invoked through this workflow counts as substantial.

## 3. Tests first

- For each piece of business logic: write a failing unit test, watch it fail, then implement until green. Repeat in small cycles.
- For each higher-level acceptance criterion: write an end-to-end integration test that drives the real UI in a headless browser.
- Never touch anything under `test/contract/` (see AGENTS.md).

## 4. Implement

Implement until all new and existing tests pass. Keep it minimal: the project's core value is that it is only good when nothing more can be removed.

## 5. Visual QA

If the feature has any UI, run the `/visual-qa` workflow on the affected screens. Fix what you find before opening the PR.

## 6. PR

- Commit in coherent steps, messages in English, no co-author trailers.
- Push and open the PR with `gh pr create` (not as a draft). Title and description in English. The description lists what was built, the tests that cover it, and the visual QA result.

## 7. Review

With the PR open, run the saved multi-agent review directly with the Workflow tool:

```
{name: 'review-pr', args: {pr: <PR number>, context: '<absolute path of the worktree>'}}
```

A feature PR always counts as substantial. Do not downgrade to an inline review and do not skip this step. Apply all confirmed findings as fix commits on the branch; treat unverified pass-through findings as leads to check yourself. Then report to the user with the PR link. Do not merge.
