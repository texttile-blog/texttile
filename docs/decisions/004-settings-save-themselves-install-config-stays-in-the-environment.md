# ADR-004: Settings save themselves; install configuration stays in the environment

## Status
Accepted

## Date
2026-08-04

## Context
Two kinds of configuration exist. Some values are fixed when the server is
installed: where the database lives, the host name, the signing secret, the
mail adapter. Other values change while you live with the site: the title,
the language, the comment rules, the upload limits, the backup switch.

## Decision
Install-time configuration is read from environment variables at boot
(`Texttile.Config`, `config/runtime.exs`). Everything that may change while
living with the site is a setting (`Texttile.Settings`): one row per key,
stored as text, an absent row meaning the default. The module owns the list of
keys, their types, their defaults and their rules. Every accepted change is
announced on the settings topic, so open screens follow it live.

Settings has no Save button. A field saves when it changes. The one exception
is the field that owns the account: moving your own address asks for the
password first.

When a feature needs a configuration switch to be bearable, the feature is
wrong. A new switch belongs in Settings with a default that fits a fresh
installation.

## Alternatives Considered

### A settings file on the volume
- Cons: a second format to parse, a second thing to validate, and no live
  update
- Rejected: one row per key in the database that is already there

### A Save button with a form
- Cons: a changed value that was not saved is a trap, and both admins may be
  on the screen at once
- Rejected: last write wins per field, as everywhere outside the lock

## Consequences
- A new setting is one key with a type, a default and a rule. No migration.
- A value that changes at runtime never needs a restart or a deploy.
- A setting that must be true at boot (the paths, the secret) is not a
  setting. It is an environment variable in the README table.

## Sources
- #5 "Settings: the round-13 settings screen, user management, uploads and image renditions"
- `AGENTS.md`, "Minimal, and everybody is an admin"
- `lib/texttile/settings.ex`, `lib/texttile/config.ex`
