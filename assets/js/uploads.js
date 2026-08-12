/* Images into the body, the GitHub way: a token holds the caret's
   place while the file travels; the token becomes the reference on
   success and a failure marker on error.

   This module is the queue, the requests and the token rewriting -
   everything about an upload that lives only in this browser. It
   talks to the editor through a handful of functions the hook hands
   it, and it reports outward through one `notify` call per change:
   the standing state (for the progress display) and the news (for the
   entry's Log). The hook crosses the LiveView seam once, with that.

   The token shapes come from the server (data-tokens on the host),
   because Texttile.Articles.Body reads exactly these markers back out
   of the words; the defaults here are the same strings, for a host
   that says nothing. */

import {t} from "./i18n.js"

const DEFAULT_TEMPLATES = {uploading: "Uploading %{name}…", failed: "Upload failed: %{name}"}

const escRx = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

export function tokensFrom(templates) {
  const shapes = {...DEFAULT_TEMPLATES, ...(templates || {})}
  const fill = (tpl, name) => tpl.split("%{name}").join(name)
  const part = tpl => escRx(tpl).replace(escRx("%{name}"), "(.+?)")
  const marker = () =>
    new RegExp("!\\[(?:" + part(shapes.uploading) + "|" + part(shapes.failed) + ")\\]\\(\\)", "g")

  return {
    up: name => "![" + fill(shapes.uploading, name) + "]()",
    fail: name => "![" + fill(shapes.failed, name) + "]()",
    done: (name, url) => "![" + name.replace(/\.\w+$/, "") + "](" + url + ")",

    /* every name the words already speak for: standing markers, and
       the file names of finished references */
    usedNames: doc => {
      const used = new Set()
      for (const m of doc.matchAll(marker())) used.add(m[1] || m[2])
      for (const m of doc.matchAll(/!\[[^\]]*\]\(([^)]+)\)/g)) used.add(m[1].trim().split("/").pop())
      return used
    },
  }
}

export function createUploads({tokens, uploadUrl, csrf, maxMb, editor, notify, request}) {
  const entries = new Map() /* name → {file, xhr, status, pct} */
  const queue = []
  let running = 0
  const mkRequest = request || (() => new XMLHttpRequest())

  const standing = () =>
    [...entries].map(([name, e]) => ({
      name,
      status: e.status === "failed" ? "failed" : "uploading",
      pct: e.pct || 0,
    }))

  const tell = news => notify({files: standing(), news})

  function add(files) {
    if (editor.readOnly()) { editor.refuse(); return }
    const news = []

    /* A file over the roof is turned away here, before a token stands
       in the text: sending it would end at the parser after the whole
       upload, and the words would carry a failed picture until
       somebody removed it by hand.

       The number is read now and not kept from the mount. The editor
       listens for setting changes, so the host carries the current
       roof; a value kept from the mount would let an editor that has
       been open all morning send a file the server has stopped
       taking. */
    const roofMb = maxMb()
    const roof = roofMb * 1024 * 1024
    const tooBig = files.filter(f => f.size > roof)
    if (tooBig.length) {
      news.push({kind: "too_big", names: tooBig.map(f => f.name || t("the pasted picture")), roof: roofMb})
      files = files.filter(f => f.size <= roof)
      if (!files.length) { tell(news); return }
    }

    const used = tokens.usedNames(editor.doc())
    for (const name of entries.keys()) used.add(name)

    const names = files.map(f => {
      let name = (f.name || "pasted-image.png").replace(/[\[\]()]/g, "")
      if (used.has(name)) {
        const dot = name.lastIndexOf(".")
        const base = dot > 0 ? name.slice(0, dot) : name
        const ext = dot > 0 ? name.slice(dot) : ""
        let i = 2
        while (used.has(base + "-" + i + ext)) i++
        name = base + "-" + i + ext
      }
      used.add(name)
      entries.set(name, {file: f, xhr: null, status: "queued", pct: 0})
      return name
    })

    editor.insert(names.map(n => tokens.up(n)).join("\n\n"))
    news.push({kind: "inserted", names})
    tell(news)
    names.forEach(n => queue.push(n))
    pump()
  }

  function pump() {
    while (running < 2 && queue.length) {
      const name = queue.shift()
      if (entries.has(name)) start(name)
    }
  }

  /* a finished, failed or cancelled request gives its slot back and
     the queue moves on. Named here and not inside start(), because a
     cancel arrives from outside the request's own listeners. */
  function settle() {
    running--
    pump()
  }

  function start(name) {
    const entry = entries.get(name)
    running++
    entry.status = "uploading"
    const xhr = mkRequest()
    entry.xhr = xhr
    xhr.open("POST", uploadUrl)
    const token = csrf()
    if (token) xhr.setRequestHeader("x-csrf-token", token)
    xhr.upload.addEventListener("progress", e => {
      if (!e.lengthComputable) return
      entry.pct = Math.round((e.loaded / e.total) * 100)
      tell([])
    })
    xhr.addEventListener("load", () => {
      settle()
      if (xhr.status === 200) {
        const {url} = JSON.parse(xhr.responseText)
        editor.swap(tokens.up(name), tokens.done(name, url))
        entries.delete(name)
        tell([{kind: "done", name}])
      } else if (xhr.status === 409 && refusedName(xhr)) {
        /* the picture is in this entry already: nothing failed and a
           retry would answer the same, so the token leaves the text
           and the news names the picture it is */
        const of = refusedName(xhr)
        dropToken(tokens.up(name))
        entries.delete(name)
        tell([{kind: "refused", name, of}])
      } else {
        fail(name, entry)
      }
    })
    xhr.addEventListener("error", () => {
      settle()
      fail(name, entry)
    })
    const form = new FormData()
    form.append("file", entry.file, name)
    xhr.send(form)
  }

  function fail(name, entry) {
    editor.swap(tokens.up(name), tokens.fail(name))
    entry.status = "failed"
    tell([{kind: "failed", name, pct: entry.pct || 0}])
  }

  function dropToken(raw) {
    if (!editor.swap(raw + "\n\n", "")) editor.swap(raw, "")
  }

  function retry(name) {
    if (editor.readOnly()) { editor.refuse(); return }
    const entry = entries.get(name)
    if (!entry || !entry.file) {
      /* the browser that held the file is gone (a reload, the other
         side): nothing to send again */
      tell([{kind: "retry_missing", name}])
      return
    }
    editor.swap(tokens.fail(name), tokens.up(name))
    entry.status = "queued"
    entry.pct = 0
    tell([{kind: "retried", name}])
    queue.push(name)
    pump()
  }

  function remove(name, how) {
    if (editor.readOnly()) { editor.refuse(); return }
    const entry = entries.get(name)

    /* an aborted request fires neither load nor error, so the slot it
       held is given back right here; a queued or failed entry holds
       none */
    if (entry && entry.status === "uploading") {
      if (entry.xhr) { try { entry.xhr.abort() } catch (_e) {} }
      settle()
    }

    entries.delete(name)
    dropToken(how === "cancel" ? tokens.up(name) : tokens.fail(name))
    tell([{kind: "removed", name, how}])
  }

  function abortAll() {
    for (const entry of entries.values()) {
      if (entry.xhr) { try { entry.xhr.abort() } catch (_e) {} }
    }
  }

  function refusedName(xhr) {
    try { return JSON.parse(xhr.responseText).of || null } catch (_e) { return null }
  }

  return {add, retry, remove, abortAll}
}
