# ADR-024: The build carries its version from `mix.exs`, and every build gets five image tags

## Status
Superseded by ADR-028 (the version comes from the Git tag). The five tags
and the rule that an exact tag never moves still stand.

## Date
2026-08-11

## Context
The publish workflow read nothing but the branch: every build on `main`
became `latest` and a commit name, and nothing said which build an
installation ran. A site could stay on one build only by writing down a sha.

## Decision
The publish reads the version from `mix.exs` and gives the build five tags:
the exact version and the commit sha, which never move, and the minor, the
major and `latest`, which follow the newest build that fits them. So a site
runs `3` and gets repairs and new capabilities, `3.0` to get repairs only,
and `3.0.1` where nothing may move. The exact tag must not exist yet: a
merge that keeps the version of the build before it stops the publish, and
only the registry's own word for an absent tag lets a build go on. Settings
shows the version of the running build, behind the sign-in.

## Alternatives Considered

### `latest` only
- Rejected: an installation must be able to pin, and the README must be
  able to name a tag to run

### Version ranges resolved by the registry
- Rejected: registries resolve no version logic; a moving tag is the whole
  mechanism

## Consequences
- Every pull request had to raise the version in `mix.exs`, so two open
  pull requests always collided on that line. That cost led to ADR-028.
- A version that carried a broken build stays broken; the repair gets the
  next number.

## Sources
- #48 "The image carries its version, and the blog is ready for a real site"
- #39 "Settings names the version that runs"
- `README.md`, "Which tag to run"
