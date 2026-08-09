# AGENTS.md

Permanent project-specific rules only. Read `PHOENIX.md` before writing Phoenix code.

## Agent lifecycle

- At the start of every turn, start a dedicated `caffeinate -dimsu` process and retain its PID. Stop that exact process after the last tool or API call, immediately before the final response. Never stop a `caffeinate` process started elsewhere.

## Product

- Load nothing external at runtime: no CDN, third-party script, tracker, or captcha. Honeypot, time trap, and rate limiting are always on and have no configuration.
- Preserve user Markdown byte for byte. Never normalize, reflow, or clean it. Do not use editors that serialize Markdown from a document tree, including ProseMirror, TipTap, and Milkdown.
- Keep the body editor in one isolated hook. Inputs are text, remote updates, and read-only state. Outputs are changes, cursor, and activity pings. Nothing else may access its internals.
- Lock only the body text. Tiles, tags, settings, and publish controls remain concurrent, with last write winning per field.
- Versions contain only title and body. Delete removed images immediately. No soft deletes or orphaned files.
- Store gallery order only in `gallery_date`. Reordering and the date field update it without changing the original file or EXIF data.
- Keep irreversible actions separate and confirmed. Publishing never sends a newsletter.
- Call the signed-in area behind `/admin` the admin area in prose and code (`TexttileWeb.Admin`), never "the desk." `Admin` alone names the person. Keep existing code names such as `/admin/texts`, `TexttileWeb.TextsLive`, and `Texttile.Articles`.
- Call a blog item an **entry** in all user-facing prose, mail, and documentation. Use "text" only for its written content.

## Git and GitHub

- Write branch names, commits, and PR text in English. Add no co-author or generation trailers.
- Never work on `main`. Create every branch from `main` in a sibling worktree named `../texttile-<slug>`.
- Keep at most ten registered worktrees, including the main worktree. Before creating one, reduce the existing set to at most nine: run `wt step prune --dry-run --min-age=0s`, inspect it, then run `wt step prune --min-age=0s`. Never force removal or remove a dirty or unintegrated worktree. If safe pruning is insufficient, ask the user what to remove.
- After creating a worktree, enter it with EnterWorktree so the session and terminals follow it.
- Use `feature/<slug>` for a user-facing capability, a change spanning multiple modules, or work likely to need more than two commits. Use a short branch name for smaller changes.
- Never open draft PRs or merge PRs. Every open PR gets `/review-pr`; fix findings with commits on its branch.
- Raise the version in `mix.exs` in the same PR as the change, before you open the PR. Read the version on `main`, not on the branch, and raise it by one step: the patch number for a repair or a small change, the minor number for a new capability, the major number when behavior, stored data, or configuration breaks. Never lower it and never skip a step. Settings shows this number, and it is the only mark of which build runs.

## Configuration and runtime

- Update the public README in the same PR as any change to environment variables, ports, Docker, deployment, or Make targets.
- Keep both Fly configurations aligned. This checkout deploys `texttile-staging` to `staging.texttile.blog`; `texttile-blog/demo` deploys `texttile-demo` to `demo.texttile.blog` from the published image. Only the app name, `PHX_HOST`, and demo `[build]` section may differ. Mirror and push changes to Fly settings, ports, volume paths, and image names in the demo repository.
- Treat `/data` as the complete installation: database and uploads. Copy a live database only with `VACUUM INTO`, `.backup`, or `make db-pull`.
- Port 4000 belongs to the user. Never bind it or kill its process. Use 4440 for tests through `TEST_PORT`, and 4441 through 4449 for agent servers.
- All worktrees share the main checkout's development database and uploads. Treat them as user data. Remove only records created by the current QA or script, through application flows or exact identifiers. Never delete shared development data wholesale.

## Tests and QA

- Write the failing test first. Test business logic with unit tests and user-facing requirements through the real UI with headless browser tests.
- Never modify, weaken, or delete `test/contract/` without explicit user approval. Fix the code when a contract test fails; ask if the contract appears wrong.
- Tests that create non-transactional state, including locks, presence, registries, application environment, or uploads, must clear it. Keep shared cleanup in `test/support/data_case.ex`.
- Before a PR, run `mix test --max-cases 4`. One green run under a different command is insufficient.
- Treat a CI-only failure as an ordering or timing race until disproved. Reproduce suspected contamination by ordering the files with `--seed 0`; reproduce timing races under CPU load.
- Browser tests must enter screens through `TexttileWeb.E2E` helpers and wait for the live page, plus gallery `data-ready` where applicable, before acting.
- Complete every UI change with `/visual-qa` in a headless browser, judging desktop and mobile screenshots together.
- Never send test mail to personal addresses. Use the local preview mailbox or Resend addresses `delivered@resend.dev` and `bounced@resend.dev`. Ask before using any real recipient.

## Prose

- Apply `/ste-writing` to English PR text, documentation, errors, and UI copy. Use strict mode for procedures and errors, flavored mode elsewhere. Never use em dashes.
