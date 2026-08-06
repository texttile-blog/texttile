# The import format

Texttile imports texts from a zip archive of bundles. A bundle is one folder
that holds one text: its Markdown, its settings, and its pictures. The format
is made for converters: a script or an AI agent reads an export from another
system (for example WordPress) and writes bundles. This document is the
complete contract. A converter that follows it needs no other knowledge of
Texttile.

The import runs in two steps. First a dry run validates every bundle and
reports errors and warnings. Nothing is created. Then the import creates or
updates the texts. The importer downloads remote pictures itself, so a bundle
can point to pictures that are still online. The zip then stays small.

## The zip

The root of the zip holds one folder per text. Each folder holds an
`index.md` file. Everything else in the folder is bundle files, available to
`index.md` through relative paths.

```
export.zip
├── my-first-text/
│   ├── index.md
│   ├── map.png
│   └── gallery/
│       ├── 001.jpg
│       └── 002.jpg
└── another-text/
    └── index.md
```

Files at the zip root and empty folders are warnings. All text is UTF-8.

## index.md

`index.md` starts with a front matter block between two `---` lines. The
Markdown body follows. The body is the text as the reader will see it,
in [CommonMark](https://commonmark.org) Markdown.

```
---
title: Beach days
slug: beach-days
date: 2019-06-02
type: post
tags: [travel, sea]
preview: gallery/001.jpg
gallery:
  - gallery/001.jpg
  - gallery/002.jpg
  - https://old-blog.example/wp-content/uploads/2019/06/beach-04.jpg
---
The map of the trip:

![The map](map.png)
```

## Front matter syntax

The front matter is a restricted subset of YAML. The importer parses exactly
this subset. Do not use other YAML features.

- The first line of the file is `---`. The block ends at the next `---` line.
- One entry per line: `key: value`, with the key at the start of the line.
- A list is either inline, `key: [a, b]`, or a block:

  ```
  key:
    - first value
    - second value
  ```

  A block list item starts with two spaces, a dash, and a space.
- A value can stand in double quotes. The quotes are removed. Inside a
  quoted value, write `\"` for a double quote and `\\` for a backslash. Use
  quotes when a value starts with `[` or contains `: `.
- Empty lines inside the block are allowed and mean nothing.
- There is no comment syntax, no nesting, and no maps.
- A key this document does not define is an error. This catches typos.

## Front matter keys

| Key              | Required | Value                                                          |
| ---------------- | -------- | -------------------------------------------------------------- |
| `title`          | yes      | The title of the text.                                         |
| `slug`           | no       | The address of the text. Default: made from the title.         |
| `date`           | no       | The publish date, `YYYY-MM-DD`. Default: the day of the import.|
| `status`         | no       | `published` or `draft`. Default: `published`.                  |
| `type`           | no       | `post` or `page`. Default: `post`.                             |
| `tags`           | no       | A list of tags.                                                |
| `allow_comments` | no       | `true` or `false`. Default: `true`.                            |
| `preview`        | no       | The source of the preview picture. See below.                  |
| `gallery`        | no       | The tiles of the text, as a list of sources. See below.        |

Details:

- `slug`: lowercase letters, digits, and dashes. The importer normalizes any
  other slug the same way it normalizes titles. Two bundles in one zip must
  not resolve to the same slug. That is an error.
- `status: published` with a `date` in the future schedules the text. It goes
  live on that day.
- The import never sends notification mails, whatever the status is.
- `preview`: the value must be byte-identical to one picture source of the
  bundle (a `gallery` entry or a body reference). Without `preview`, the
  first picture of the text speaks for it.

## Picture sources

Everywhere a picture appears (a `gallery` entry, a `preview` value, an image
reference in the body), the source is one string with two possible forms:

- A relative path to a file in the bundle folder, for example
  `gallery/001.jpg` or `map.png`. The path must stay inside the bundle
  folder. `..` is an error.
- An `http:` or `https:` URL. The importer downloads the file at import
  time.

Both forms mean the same thing: the picture becomes a local upload. A bundle
can never produce a picture that stays hotlinked.

The same source string used twice, in one bundle, becomes one upload. The
comparison is byte-identical strings, so write each URL one way.

Supported picture formats: PNG, JPEG, WebP, and GIF. The dry run checks each
URL with a HEAD request and reports dead URLs and non-picture content types.
The report also lists every host the bundle downloads from. Check that list
for hosts you do not expect.

## The gallery

The gallery holds the tiles of a text. There are two ways to define it:

- The `gallery` key: a list of sources. The order of the list is the order
  of the tiles.
- The shorthand: no `gallery` key, and a `gallery/` folder in the bundle.
  Every picture file in that folder becomes a tile, sorted by file name.

When the `gallery` key exists, it alone decides. A file in `gallery/` that
the key does not list is a warning, not a tile.

## Pictures in the body

Every Markdown image reference in the body, `![alt](source)`, is imported.
The importer rewrites the reference to the address of the new upload. Links
that are not image references stay as they are.

## Validation

The dry run reports per bundle. Errors stop the bundle from importing.
Warnings do not.

Errors:

- `index.md` is missing, or its front matter does not parse.
- An unknown front matter key, a wrong value, or a missing `title`.
- Two bundles resolve to the same slug.
- A relative source points to a file that is not in the bundle.
- A URL is dead, or its content is not a supported picture.
- A `preview` value that matches no picture source of the bundle.

Warnings:

- A file in the bundle that nothing references.
- A file in `gallery/` that an explicit `gallery` key does not list.
- A slug that already exists on the site. The import updates that text.
- A file at the zip root, or an empty folder.

## Importing twice

The slug identifies the text. When the slug already exists, the import
updates that text: title, body, settings, and date. The gallery is replaced
with the gallery of the bundle. Pictures of the earlier import that the
bundle no longer references are deleted. An import with the same zip twice
gives the same site, not duplicates.

## Reserved

A `comments.yaml` file in a bundle is reserved for a later version. The
importer ignores it today, without a warning.
