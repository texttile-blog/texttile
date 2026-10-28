# ADR-007: The writer's Markdown is stored byte for byte, behind one isolated editor hook

## Status
Accepted

## Date
2026-08-06

## Context
A version diff is only useful when it shows real edits. Two people write the
same entry, and one watches the other's text arrive live. The editor is the
heaviest JavaScript the admin area carries, and it must never reach the
reader.

## Decision
The body is plain text, not a document tree. What the writer typed is what is
stored, character for character. Nothing normalizes, reflows or cleans
Markdown. Raw HTML in the source is shown as text, never executed
(`Texttile.Markdown`).

The editor is CodeMirror 6 with an Obsidian-style live preview: Markdown is
the document, everything visible is a view-only decoration, and raw syntax
shows on the line with the cursor. It is bundled from npm, loaded as its own
chunk the moment an editor is on screen, and never on the grid, the settings
or the sign-in. The `BodyEd` hook is the only door: text, remote updates and
a read-only flag go in; debounced changes, cursor and activity pings come
out. Nothing else may reach into it.

## Alternatives Considered

### A tree-based editor (ProseMirror, TipTap, Milkdown)
- Pros: rich editing, structured documents
- Cons: the editor serializes the Markdown from a tree, so a save rewrites
  what the writer did not touch and a diff shows noise
- Rejected: it breaks the byte-for-byte promise

### A plain textarea
- Pros: no JavaScript weight
- Cons: no live preview, no syntax help, and remote updates would move the
  caret
- Rejected after the first round: CodeMirror behind the same contract

## Consequences
- A formatting bar or a hint inserts text; it never rewrites the document.
- Remote keystrokes from the lock holder land in the watcher's read-only view
  through the same hook inputs.
- The editor chunk weighs most of a megabyte and must stay out of every page
  that is not the editor.

## Sources
- #10 "The editor experience: writing, publishing, versions, and the soft lock"
- #24 "Write down the principles and the product decisions"
- `assets/js/body_ed.js`, `assets/js/body_ed_core.js`, `lib/texttile/markdown.ex`
