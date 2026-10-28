# Architecture decision records

One file per decision that would be expensive to reverse: why it was made,
what it ruled out, and what it costs. The code shows what was built; these
files say why.

The first 28 records were written in October 2026 from the commit history,
the pull requests, `README.md` and `AGENTS.md`. Each one names its sources.
Where a source names the alternative that was rejected, the record repeats
it; where it does not, the record names what the decision rules out as the
sources describe it.

## How to add one

- Copy the headings of any record: Status, Date, Context, Decision,
  Alternatives Considered, Consequences, Sources.
- Number it next in line, `030-short-title.md`, and link it from the table.
- Never delete or rewrite a record. When a decision changes, write a new one
  that supersedes the old, and mark the old one superseded.
- Write the record in the pull request that makes the decision, in the prose
  rules of `AGENTS.md`: entry, admin area, no em dash.

## The records

| ADR | Decision | Date |
| --- | --- | --- |
| [001](001-one-phoenix-app-one-sqlite-file-one-volume.md) | One Phoenix app, one SQLite file, one Docker image, one volume | 2026-08-02 |
| [002](002-mail-adapter-chosen-at-runtime.md) | Mail leaves through a Swoosh adapter chosen at runtime | 2026-08-02 |
| [003](003-worktrees-share-one-development-database.md) | Worktrees share one development database; the dev server is on the network | 2026-08-03 |
| [004](004-settings-save-themselves-install-config-stays-in-the-environment.md) | Settings save themselves; install configuration stays in the environment | 2026-08-04 |
| [005](005-originals-kept-renditions-on-demand.md) | Originals are kept; renditions are made on demand and thrown away | 2026-08-04 |
| [006](006-tests-prove-each-promise-at-one-layer.md) | Tests prove each promise at one layer, and take the SQLite write lock | 2026-08-04 |
| [007](007-markdown-byte-for-byte-codemirror-behind-one-hook.md) | Markdown is stored byte for byte, behind one isolated editor hook | 2026-08-06 |
| [008](008-soft-lock-on-title-and-body-as-a-genserver.md) | The soft lock on title and body is a GenServer; everything else stays free | 2026-08-06 |
| [009](009-versions-hold-title-and-body-on-deliberate-actions.md) | A version holds title and body, made on deliberate actions only | 2026-08-06 |
| [010](010-gallery-order-lives-in-gallery-date.md) | The gallery's order lives in `gallery_date` | 2026-08-06 |
| [011](011-reader-pages-are-controllers-the-admin-area-is-liveview.md) | Reader pages are controllers; the admin area is LiveView | 2026-08-06 |
| [012](012-import-and-export-share-one-bundle-format.md) | Import and export share one bundle format, a Hugo page bundle | 2026-08-06 |
| [013](013-posts-live-under-their-date-and-a-move-leaves-a-redirect.md) | A post lives under its date; a move leaves a permanent redirect | 2026-08-07 |
| [014](014-comments-wait-for-the-reader-never-for-an-admin.md) | A comment waits for its reader's confirmation, never for an admin | 2026-08-07 |
| [015](015-spam-protection-without-a-captcha.md) | Spam protection is three invisible filters, never a captcha | 2026-08-07 |
| [016](016-newsletter-double-opt-in-one-mail-per-entry.md) | The newsletter is double opt-in and sends one mail per entry | 2026-08-07 |
| [017](017-nothing-is-loaded-from-outside.md) | Nothing is loaded from outside | 2026-08-08 |
| [018](018-one-shared-password-guards-the-blog-or-nothing.md) | One shared password guards the blog or nothing; a guarded blog has no feed | 2026-08-08 |
| [019](019-video-is-converted-once-by-ffmpeg-gently.md) | A video is converted once by ffmpeg, one at a time, at the lowest priority | 2026-08-08 |
| [020](020-readers-are-counted-here-with-a-daily-salt-and-no-cookie.md) | Readers are counted here, with a daily salt and no cookie | 2026-08-08 |
| [021](021-a-blog-speaks-one-language-one-gettext-file-per-language.md) | A blog speaks one language; one gettext file per language | 2026-08-08 |
| [022](022-a-live-entry-keeps-two-texts.md) | A live entry keeps two texts; every reader path takes the live one | 2026-08-10 |
| [023](023-backup-by-pull.md) | The backup pulls; the server holds nothing that reaches the copies | 2026-08-10 |
| [024](024-the-build-carries-its-version-from-mix-exs.md) | The build carries its version from `mix.exs`; five image tags (superseded by 028) | 2026-08-11 |
| [025](025-publish-and-deploy-wait-for-a-green-ci-run.md) | The publish and the deploy start from a green CI run of the same commit | 2026-08-14 |
| [026](026-the-email-address-is-the-identity-and-everybody-is-an-admin.md) | The email address is the identity; everybody is an admin; a deleted account keeps its row | 2026-08-19 |
| [027](027-staging-runs-on-bunny-magic-containers.md) | Staging runs on Bunny Magic Containers; Fly stays as recovery (Fly part superseded by 029) | 2026-10-17 |
| [028](028-the-version-comes-from-the-git-tag-and-a-label.md) | The version comes from the Git tag, counted up by a label | 2026-10-23 |
| [029](029-the-fly-configuration-is-gone.md) | The Fly configuration is gone; Bunny is the only host the repository knows | 2026-10-28 |
