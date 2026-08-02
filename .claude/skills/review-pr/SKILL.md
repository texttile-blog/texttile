---
name: review-pr
description: Review an open PR in depth and apply fixes directly as commits on the PR branch. Use when a PR is open or the user asks for a review.
---

# PR review workflow

Reviews here are not comment threads. Findings get fixed directly on the branch while the PR is open.

## 1. Load the PR

Identify the PR (argument, or the PR of the current branch via `gh pr view`). Read the full diff with `gh pr diff` plus enough surrounding code to judge it in context, not just the changed lines.

## 2. Review

**Substantial PRs** (feature PRs, anything beyond a small fix): run the saved multi-agent workflow with the Workflow tool: `{name: 'review-pr', args: {pr: <number>}}`. It fans out one reviewer per dimension in parallel and adversarially verifies each finding. Work from the confirmed findings it returns; treat unverified pass-through findings as leads to check yourself.

**Small PRs**: review inline yourself along the same dimensions:

- **Correctness**: bugs, edge cases, race conditions (multiplayer editing makes this a first-class concern).
- **Tests**: Was this test-driven? Does every piece of business logic have a unit test? Do the e2e tests actually cover the acceptance criteria, or only the happy path? Are contract tests untouched?
- **Minimalism**: Can anything be removed? Unnecessary abstractions, dead code, dependencies that a few lines of code would replace. This project is only good when nothing more can be removed.
- **Frontend weight**: data frugality is a core value. Flag anything that ships unnecessary JavaScript or payload to the frontend.
- **Security**: auth, input handling, uploads, anything user-generated (comments, markdown).

In both cases: if the PR touches the UI and there is no fresh visual QA result, run `/visual-qa` now.

## 3. Fix directly

Apply every fix as a commit on the PR branch and push. English commit messages, no co-author trailers. Only leave something unfixed if it needs a user decision; then say so explicitly in the summary.

## 4. Verify and summarize

Run the full test suite after the fixes. Then post a summary comment on the PR with `gh pr comment`: findings, what was fixed, what (if anything) is left open and why. Report the result to the user. Do not merge.
