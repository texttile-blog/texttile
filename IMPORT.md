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

The report and the import both go by date, oldest text first. A bundle
without a `date` comes last, under its folder name.

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
The archive may hold up to 20,000 entries and up to 4 GB unpacked; a
larger one is refused whole.

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
| `title`          | yes      | The title of the text, up to 500 characters.                   |
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
  not resolve to the same slug. That is an error. A post then lives at
  `/2019/06/02/beach-days`, its date and its slug; a page lives at
  `/about-us`, its slug alone.
- `status: published` with a `date` in the future schedules the text. It goes
  live on that day.
- The import itself sends no mail, and a text imported as published
  counts as already told about. A text the import schedules goes live
  on its day like any scheduled text, subscriber notification included.
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
URL with a HEAD request (and a one-byte GET when the host refuses HEAD) and
reports dead URLs and non-picture content types. The report also lists every
host the bundle downloads from. Check that list for hosts you do not expect.

Three rules keep the fetches honest. A URL must answer directly; a redirect
is an error, so write the final address. A URL must not point at the
server's own network; loopback and private addresses are refused. And one
picture may hold up to 100 MB; a larger one is an error.

## Check every URL before you write the zip

An export from an old system is full of addresses that died years ago. Test
them while you convert, not when the import runs. Request each picture URL
one time and read the status code and the content type. Only a URL that
answers 200 belongs in a bundle.

For each URL:

- **200 with a picture content type**: write the URL into the bundle.
- **404, 403, 410, or 5xx**: the picture is gone. Do not write the URL.
  Put a local copy in the bundle folder if you have one, or remove the
  reference from the front matter and the body.
- **301 or 302**: the importer refuses a redirect. Follow it yourself and
  write the address it ends at.
- **200 with `text/html`**: the host answers with a page, not a picture.
  Treat it as dead.
- **405 or 501 on HEAD**: the host refuses HEAD. Ask again with a one-byte
  range GET.

One request per URL is enough. This command prints the status, the final
address, and the content type of one URL:

```
curl -sIL -o /dev/null -w '%{http_code} %{content_type} %{url_effective}\n' URL
```

Write a short list of every URL you dropped, and give it to the person who
runs the import. They then know what is missing before the texts are live.

A converter that skips this check hands the dry run a list of dead pictures,
and the work starts again at the export.

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
- A title longer than 500 characters.
- Two bundles resolve to the same slug.
- A URL that redirects, points at a private address, or is larger than
  the picture cap.
- A relative source points to a file that is not in the bundle.
- A URL is dead, or its content is not a supported picture.
- A gallery entry that appears twice in the list.
- A `preview` value that matches no picture source of the bundle.

Warnings:

- A file in the bundle that nothing references.
- A file in `gallery/` that an explicit `gallery` key does not list.
- A slug that already exists on the site. The import updates that text.
- A text somebody has open in the editor right now. The run refuses
  that bundle while the editor stays open; run the import again later.
- A file at the zip root, or an empty folder.

## Importing twice

The slug identifies the text. When the slug already exists, the import
updates that text: title, body, settings, and date. The gallery is replaced
with the gallery of the bundle. Pictures of the earlier import that the
bundle no longer references are deleted. An import with the same zip twice
gives the same site, not duplicates.

## Comments

A bundle can carry the comments of its text in a `comments.yaml` file.
The format stands now so a converter can already write it; the importer
reads the file in a later version and ignores it today, without a
warning. Export only the comments that belong on the site; there is no
status field.

```
- author: Christiane
  email: christiane@example.org
  date: 2026-07-30 22:14
  id: 12
  text: |
    Ihr Lieben, immer wieder!

    Es war ein Fest mit euren Jungs.
- author: kb
  date: 2026-07-31 09:02
  reply_to: 12
  text: |
    Danke euch!
```

Like the front matter, this is a restricted subset of YAML:

- The file is a list. A comment starts with `- ` at the start of a
  line. Its other fields follow, indented with two spaces.
- `text: |` opens the comment text. Every following line that is
  indented with four spaces belongs to it, with the indent removed.
  Empty lines inside the text are kept.
- All other values are single-line scalars, quoted or plain, with the
  same quoting rules as the front matter.

The fields:

| Field      | Required | Value                                                  |
| ---------- | -------- | ------------------------------------------------------ |
| `author`   | yes      | The displayed name.                                    |
| `text`     | yes      | The comment, plain text.                               |
| `date`     | yes      | `YYYY-MM-DD HH:MM` or with seconds, local wall clock.  |
| `email`    | no       | The address the author gave.                           |
| `website`  | no       | The URL the author gave.                               |
| `id`       | no       | A number, unique in the file. Only replies need it.    |
| `reply_to` | no       | The `id` of the comment this one answers.              |

There are no avatars in the format. WordPress avatars are Gravatars,
computed from the email address; the address keeps that door open
without storing third-party pictures.
