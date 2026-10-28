# ADR-021: A blog speaks one language, and one gettext file per language holds every word

## Status
Accepted

## Date
2026-08-08

## Context
The entries are written in one language, so the words around them should be
too. A reader has no profile to carry a language preference. Sentences a
person reads come from templates, from Ecto errors, from mail and from the
browser's own scripts.

## Decision
A blog has one language, picked in Settings > Site. English and German ship.
`Texttile.I18n` owns the list and hands the language to every process that
writes words: a request gets it from a plug, a LiveView from an `on_mount`,
because Gettext holds the locale per process.

English is the language of the source and has no translation file: every
msgid is the English sentence, so a missing translation reads as English.
Each other language is exactly one file,
`priv/gettext/<code>/LC_MESSAGES/default.po`, with the error messages and
the browser sentences included. Ecto's messages are listed in
`TexttileWeb.EctoMessages` so the extractor sees them. Sentences the browser
says live in `TexttileWeb.JsStrings` and reach `assets/js/i18n.js` as
`data-words`, keyed by the English sentence. Month names are translated in
`I18n`, because Elixir takes no other language for dates. The feed keeps
English dates, as RFC 822 asks.

## Alternatives Considered

### A language per reader from `Accept-Language`
- Rejected: the entries are in one language; a German blog with English
  buttons is wrong

### Several gettext domains
- Rejected: one file per language is one thing to translate and one test
  (`translations_test.exs`) that names every gap

## Consequences
- Every sentence a person reads goes through `gettext`. `mix precommit`
  refuses an out-of-date template.
- Adding a language is one tuple in `@languages`, one merged file, and a
  translation pass.
- What the writer writes is never touched.

## Sources
- #31 "The blog speaks one language, and one file per language holds its words"
- `lib/texttile/i18n.ex`, `README.md`, "Language"
