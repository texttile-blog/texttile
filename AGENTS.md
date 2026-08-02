# AGENTS.md

Rules for agents working in this repository. Only deviations from default behavior are listed here. Product requirements live in `idea.md`, not here. Framework-specific guidance (Phoenix, LiveView, Ecto, HEEx) lives in `PHOENIX.md`; read it before writing Phoenix code.

## Git and GitHub

- Branch names, commit messages, and PR titles/descriptions are always written in English.
- Never add a co-author trailer to commits. No `Co-Authored-By`, no "Generated with Claude Code" lines, in neither commits nor PR descriptions.
- Use the `gh` CLI for everything GitHub-related: PRs, reviews, comments, CI status.
- Open PRs ready for review, never as drafts.
- Every substantial new feature is developed in its own git worktree on a feature branch (`feature/<slug>`). Substantial means: it adds a user-facing capability, touches more than one module, or will take more than a couple of commits. Small fixes and chores may use a plain branch in the main checkout.
- Do not merge PRs. Open them, review them, fix them. Merging is the user's decision.

## Ports

- Port 4000 belongs to the user (`make start`). Never start anything on it and never kill what runs there.
- Agents use ports 4440-4449: the test server runs on 4440 (override with `TEST_PORT`), ad-hoc dev servers (visual QA, manual checks) run with `PORT=4441` and up.

## Test-driven development

- Write the failing test first, then the implementation. No business logic without a unit test that motivated it.
- Higher-level requirements get end-to-end integration tests that exercise the app through the real UI (headless browser), not just the API layer.
- There are two classes of tests:
  - **Working tests**: written and freely adapted by the agent as the design evolves.
  - **Contract tests** (everything under `test/contract/`): defined by the user. Never modify, weaken, or delete a contract test without an explicit user request. If a contract test fails, fix the code. If you believe the test itself is wrong, stop and ask.

## UI verification

- A UI change is not done when the tests pass. It is done after you have used the feature yourself in a headless browser, looked at screenshots, and judged the result. Run the `/visual-qa` workflow before opening a PR that touches the UI.
- Always evaluate desktop and mobile viewports together, never desktop only.

## Writing style

- All English prose output (PR descriptions, commit bodies, docs, READMEs, error messages, release notes, UI copy) follows the `/ste-writing` skill: strict mode for procedures and error messages, STE-flavored mode for everything else. Never use em dashes.

## Pull requests

- Every PR gets a full review while it is open, via the `/review-pr` workflow. Findings are fixed directly with commits on the PR branch, not left as comments for someone else.

## Workflows

- `/feature` — build a substantial feature: worktree, TDD, visual QA, PR, review.
- `/review-pr` — review an open PR and apply fixes directly.
- `/visual-qa` — use the app in a headless browser, screenshot desktop and mobile, judge the layout.
- `/ste-writing` — rewrite prose into Simplified Technical English (see Writing style).
