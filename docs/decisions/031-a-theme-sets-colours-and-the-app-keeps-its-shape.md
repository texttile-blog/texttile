# ADR-031: A theme sets colours, and the app keeps its shape

## Status
Accepted

## Date
2026-11-09

## Context
A stored theme (Settings > Theme) was a whole stylesheet, loaded after app.css.
The settings screen showed the default sheet to edit, so one changed colour
stored the whole default as it was that day. That copy then won over every
later default. Staging had saved the default of August, in which a field is a
line, and kept flat fields after the UI polish of November made a field a
white box. Nothing in the code had changed for staging; its stored copy had
frozen the look.

## Decision
The tokens of the default theme, `assets/css/theme.css`, are the contract: the
colours, the corners and `color-scheme`. A stored theme sets those and nothing
else.

- How a field and the writing surface are drawn (`--fld-*`, `--edt-*`,
  `--edb-*`) is the app's own and lives in `base.css`, built from the theme's
  colours. The frame colour of a field became a token of its own,
  `--tt-fieldline`.
- A save keeps only the tokens whose value leaves the default, as one `:root`
  rule. A colour nobody touched goes on following the default.
- `/theme.css` serves that rule and nothing else. A theme stored before this
  decision is held to the contract when it is served, so it needs no
  migration.
- The settings screen shows the default sheet with the stored values in their
  place, and names what a save left out.

## Alternatives Considered

### Keep the whole sheet and ask people to reset after an update
- Rejected: nobody knows which update to reset for, and a reset throws away
  the colours they chose

### Colour pickers instead of the CSS field
- Not now: it solves the same problem with much more UI. The contract above
  is what a picker would write, so it stays open

### Version the tokens, so an old theme keeps an old field
- Rejected: two field designs to keep alive, for a look nobody chose

## Consequences
- A rename or removal of a token drops that value from every stored theme
  that set it. Say so in the release.
- A theme can no longer carry its own rules (a selector, an `@media` block).
  Only tokens reach the page.
- An untouched install serves an empty `/theme.css`; the default is bundled in
  app.css.
- A colour that a stored copy of an older default still carries stays at that
  value until the theme is reset or the line is removed.

## Sources
- Staging's stored theme, November 2026: the round-19 default of #46, byte for
  byte
- `lib/texttile/settings/theme.ex`, `assets/css/theme.css`, `assets/css/base.css`
