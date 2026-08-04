

**Editor**

- CodeMirror 6, gekapselt als einzelner LiveView-Hook; Container mit `phx-update="ignore"`.
- Markdown _is_ the document — a plain text buffer. No AST, no serialization step, no tree-to-markdown conversion.
- **Byte-identical round-trip is a hard requirement.** All rendering happens via view-only decorations. Never rewrite the user's markdown: no normalizing `*` to `_`, no reflowing, no whitespace cleanup. The version diff must only ever show real edits.
- **Obsidian-style live preview:** markdown syntax is hidden and the result rendered inline on inactive lines; raw syntax is revealed on the line containing the cursor and inside the current selection.
- Render inline: headings, bold, italic, inline code, links, blockquotes, lists, task lists, code blocks, horizontal rules, and images as inline thumbnails. Tables: aligned at minimum, full inline rendering optional.
- Reference implementations to study: `codemirror-live-markdown` (framework-agnostic — preferred, may be used as a dependency), `atomic-editor` (React — read it for the decoration approach, do not depend on it).
- No split-pane preview. No WYSIWYG toolbar as the primary interface; a compact optional formatting bar is allowed, but the editor is keyboard- and markdown-first.
- **Mobile is the primary target.** Verify on Android/Gboard (autocorrect, word suggestions) and iOS Safari. Cursor stability while decorations mount and unmount is the main known risk in live-preview editors — test it explicitly, it is not a detail.

**Image insertion (GitHub-style)**

- Clipboard paste and drag & drop into the editor upload the file and insert `![alt](url)` at the cursor.
- Show a placeholder while uploading (e.g. `![Uploading photo.jpg…]()`), replace it on success, remove it and surface an error on failure.
- Inline body images are a separate concept from the gallery — an upload here must never add a tile to the gallery.

**Hook interface (keeps the Yjs upgrade path open, see §7)**

- in: initial text, remote text updates, read-only flag.
- out: local changes (debounced), cursor position, activity ping feeding `last_keystroke_at`.
- Read-only mode uses the same rendering with editing disabled; it must not steal focus.
- No other part of the application reads or writes editor internals.

**Explicitly not**

- Not TipTap, not Milkdown, not ProseMirror. Any editor that serializes markdown from a document tree normalizes the syntax and produces noise in the version diff.
- Rich-text paste (HTML converted to markdown) is deferred; paste as plain text in v1.