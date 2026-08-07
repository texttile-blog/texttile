# AGENTS.md

Only deviations from default behavior. Phoenix/LiveView/Ecto guidance lives in `PHOENIX.md`; read it before writing Phoenix code.

## Git and GitHub

- Branches, commits, and PR texts in English. No co-author trailers, no "Generated with" lines.
- No draft PRs. Never merge; merging is the user's decision.
- Never work on `main`. Every new branch off `main` starts as a worktree: `git worktree add ../texttile-<slug> -b <branch> main`. Substantial features (new user-facing capability, more than one module, or more than a couple of commits) use `feature/<slug>`; small fixes use a short branch name, but still get a worktree.
- After `git worktree add`, switch the session into the worktree with the EnterWorktree tool (`path`), so the session's working directory (and any terminal split) is the worktree.
- Every open PR gets a `/review-pr` pass. Findings are fixed as commits on the PR branch, not left as comments.

## README

- The README is the public setup documentation; the project will be open source. Any change to configuration (env vars, ports, Docker, deploy, make targets) updates the README in the same PR.

## Deploy config

- `fly.toml` exists twice: here (builds from source) and in the repo `texttile-blog/deploy-demo` (usually checked out at `../deploy-demo`, deploys the published image). The only intended difference is the `[build]` section. When you change `fly.toml`, env vars, ports, volume paths, or the image name, apply the same change in deploy-demo and push it.

## Ports

- 4000 belongs to the user (`make start`): never bind it, never kill what runs there.
- Agents use 4440-4449: tests on 4440 (`TEST_PORT`), ad-hoc servers on `PORT=4441` and up.

## Dev data

- All worktrees share the main checkout's dev database and uploads (`texttile_dev.db`, see config/dev.exs). That database holds the user's living test data. QA and scripts remove only the records they created themselves, through the app's own delete flows or by exact id or username. Never delete wholesale from the shared dev DB.

## Tests

- Failing test first. Business logic gets unit tests; higher-level requirements get e2e tests through the real UI in a headless browser.
- `test/contract/` is user-defined: never modify, weaken, or delete without an explicit user request. If one fails, fix the code; if the test seems wrong, stop and ask.

## Mail

- Never send mail to real personal addresses. For live delivery tests use Resend's test addresses (`delivered@resend.dev`, `bounced@resend.dev`) or the local preview mailbox. If a test ever needs a real recipient, ask the user for the address first.

## UI

- A UI change is done only after `/visual-qa`: use it in a headless browser, look at the screenshots, judge desktop and mobile together.

## Prose

- English prose (PR texts, docs, error messages, UI copy) follows `/ste-writing`: strict mode for procedures and errors, flavored elsewhere. No em dashes.
