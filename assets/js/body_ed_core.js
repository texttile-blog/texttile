/* BodyEd · the body editor behind one door.

   Markdown IS the document: the editor holds a plain text buffer and
   everything it shows is a view-only decoration. It never rewrites the
   text - no normalizing, no reflowing, no cleanup - so the version
   diff only ever shows real edits.

   Live preview, the Obsidian way: on lines away from the cursor the
   syntax is hidden and the result is shown; the line with the cursor,
   and every line the selection touches, shows the raw text. That rule
   also protects mobile IME composition, because the line being
   composed on is always undecorated raw text.

   The interface, and nothing else crosses it:
   in:  the initial text (the server-rendered textarea), sync_body
        {text, caret?}, set_readonly {readOnly}
   out: body_changed {text} (debounced), editor_activity (throttled),
        ask_takeover on a read-only pointer, files into uploadFiles */

import {EditorState, EditorSelection, Compartment, Annotation} from "@codemirror/state"
import {EditorView, keymap, placeholder, Decoration, WidgetType, ViewPlugin} from "@codemirror/view"
import {syntaxTree, syntaxHighlighting, HighlightStyle} from "@codemirror/language"
import {defaultKeymap, history, historyKeymap} from "@codemirror/commands"
import {markdown, markdownLanguage, insertNewlineContinueMarkup, deleteMarkupBackward} from "@codemirror/lang-markdown"
import {tags} from "@lezer/highlight"

/* character styling reads the theme tokens; order matters, because the
   marks' faint must win over the link's accent on shared tokens */
const mdHighlight = HighlightStyle.define([
  {tag: tags.strong, fontWeight: "700"},
  {tag: tags.emphasis, fontStyle: "italic"},
  {tag: tags.strikethrough, textDecoration: "line-through"},
  {tag: tags.heading, fontWeight: "600"},
  {tag: tags.quote, color: "var(--tt-dim)"},
  {tag: tags.monospace, fontFamily: "var(--tt-font-mono)", fontSize: "86%"},
  {tag: tags.link, color: "var(--tt-accent)", textDecoration: "underline", textUnderlineOffset: "2px"},
  {tag: tags.processingInstruction, color: "var(--tt-faint)"},
  {tag: tags.contentSeparator, color: "var(--tt-faint)"},
  {tag: tags.url, color: "var(--tt-faint)", textDecoration: "none"},
])

/* ---- the widgets the preview draws -------------------------------- */
class BulletW extends WidgetType {
  eq() { return true }
  toDOM() { const s = document.createElement("span"); s.className = "cm-mdbullet"; s.textContent = "•"; return s }
}
class HRW extends WidgetType {
  eq() { return true }
  toDOM() { const s = document.createElement("span"); s.className = "cm-mdhr"; return s }
}
class CheckW extends WidgetType {
  constructor(checked, ro) { super(); this.checked = checked; this.ro = ro }
  eq(o) { return o.checked === this.checked && o.ro === this.ro }
  ignoreEvent() { return true }
  toDOM(view) {
    const b = document.createElement("input")
    b.type = "checkbox"
    b.className = "cm-mdcheck"
    b.checked = this.checked
    b.disabled = this.ro
    b.setAttribute("aria-label", this.checked ? "Done. Untick it." : "Open. Tick it off.")
    b.addEventListener("mousedown", e => e.preventDefault())   /* the caret stays where it is */
    b.addEventListener("click", e => {
      e.preventDefault()
      if (view.state.readOnly) return
      const pos = view.posAtDOM(b)
      if (!/^\[[ xX]\]$/.test(view.state.doc.sliceString(pos, pos + 3))) return
      view.dispatch({changes: {from: pos + 1, to: pos + 2, insert: this.checked ? " " : "x"}})
    })
    return b
  }
}
class ImgW extends WidgetType {
  constructor(css, title, video) { super(); this.css = css; this.title = title; this.video = video }
  eq(o) { return o.css === this.css && o.title === this.title && o.video === this.video }
  toDOM() {
    const s = document.createElement("span")
    s.className = this.video ? "cm-mdimg cm-mdvid" : "cm-mdimg"
    if (this.css) s.style.backgroundImage = this.css
    s.title = this.title
    return s
  }
}

/* the containers Texttile.Videos takes */
export const VIDEO_FILE = /\.(mp4|mov|m4v|webm|avi|mkv)$/i

/* ---- the live preview --------------------------------------------- */
const HIDE = Decoration.replace({})
const remoteChange = Annotation.define()

function buildDeco(view, resolveImage) {
  const {state} = view
  const doc = state.doc
  const ro = state.readOnly
  const deco = []
  /* every line the selection touches shows its raw syntax; the
     read-only view has no cursor, so it is a pure preview */
  const active = []
  if (!ro) for (const r of state.selection.ranges)
    active.push([doc.lineAt(r.from).from, doc.lineAt(r.to).to])
  const showRaw = (from, to) => active.some(a => from <= a[1] && to >= a[0])
  const lineCls = (pos, cls) => deco.push(Decoration.line({class: cls}).range(doc.lineAt(pos).from))
  const eachLine = (from, to, cls) => {
    for (let i = doc.lineAt(from).number, last = doc.lineAt(to).number; i <= last; i++)
      deco.push(Decoration.line({class: cls}).range(doc.line(i).from))
  }
  const hide = (from, to) => { if (to > from) deco.push(HIDE.range(from, to)) }

  for (const vr of view.visibleRanges) {
    syntaxTree(state).iterate({from: vr.from, to: vr.to, enter: n => {
      const name = n.name
      const h = /^ATXHeading([1-6])$/.exec(name)
      if (h) {
        lineCls(n.from, "cm-mdh cm-mdh" + h[1])
        if (!showRaw(n.from, n.to)) n.node.getChildren("HeaderMark").forEach((m, i) =>
          hide(m.from, i === 0 ? Math.min(m.to + 1, n.to) : m.to))
        return   /* descend: a heading can hold emphasis */
      }
      if (name === "Emphasis" || name === "StrongEmphasis") {
        if (!showRaw(n.from, n.to)) n.node.getChildren("EmphasisMark").forEach(m => hide(m.from, m.to))
        return
      }
      if (name === "Strikethrough") {
        if (!showRaw(n.from, n.to)) n.node.getChildren("StrikethroughMark").forEach(m => hide(m.from, m.to))
        return
      }
      if (name === "InlineCode") {
        const ms = n.node.getChildren("CodeMark")
        if (ms.length === 2) {
          const raw = showRaw(n.from, n.to)
          if (!raw) ms.forEach(m => hide(m.from, m.to))
          const a = raw ? n.from : ms[0].to, b = raw ? n.to : ms[1].from
          if (b > a) deco.push(Decoration.mark({class: "cm-mdcodespan"}).range(a, b))
        }
        return false
      }
      if (name === "Image") {
        if (showRaw(n.from, n.to)) return false
        const urlN = n.node.getChild("URL")
        const url = urlN ? doc.sliceString(urlN.from, urlN.to).trim() : ""
        /* an empty target is an upload token: the raw text IS the
           placeholder, so it stays raw on every line */
        if (!url) return false
        const ms = n.node.getChildren("LinkMark")
        const alt = ms.length >= 2 ? doc.sliceString(ms[0].to, ms[1].from) : ""
        const css = resolveImage ? resolveImage(url) : null
        deco.push(Decoration.replace({widget: new ImgW(css, alt || url, VIDEO_FILE.test(url))}).range(n.from, n.to))
        return false
      }
      if (name === "Link") {
        /* only a link with a written target collapses; a bare
           [reference] stays raw, brackets and all */
        if (!n.node.getChild("URL")) return
        const ms = n.node.getChildren("LinkMark")
        if (!showRaw(n.from, n.to) && ms.length >= 2) {
          hide(ms[0].from, ms[0].to)
          hide(ms[1].from, n.to)   /* "](url)", and a title if there is one */
        }
        return
      }
      if (name === "Blockquote") { eachLine(n.from, n.to, "cm-mdquote"); return }
      if (name === "QuoteMark") {
        if (!showRaw(n.from, n.to)) hide(n.from, Math.min(n.to + 1, doc.lineAt(n.from).to))
        return
      }
      if (name === "ListMark") {
        const txt = doc.sliceString(n.from, n.to)
        if (/^\d/.test(txt)) { deco.push(Decoration.mark({class: "cm-mdnum"}).range(n.from, n.to)); return }
        const item = n.node.parent
        if (item && item.getChild("Task")) {
          /* the checkbox line: the bullet goes with the marker */
          if (!showRaw(n.from, n.to)) hide(n.from, Math.min(n.to + 1, doc.lineAt(n.from).to))
          return
        }
        if (!showRaw(n.from, n.to)) deco.push(Decoration.replace({widget: new BulletW()}).range(n.from, n.to))
        return
      }
      if (name === "TaskMarker") {
        const checked = /x/i.test(doc.sliceString(n.from, n.to))
        if (checked) lineCls(n.from, "cm-mdtaskdone")
        if (!showRaw(n.from, n.to))
          deco.push(Decoration.replace({widget: new CheckW(checked, !!ro)})
            .range(n.from, Math.min(n.to + 1, doc.lineAt(n.from).to)))
        return
      }
      if (name === "FencedCode") {
        eachLine(n.from, n.to, "cm-mdcodeblock")
        lineCls(n.from, "cm-mdcbfirst")
        lineCls(n.to, "cm-mdcblast")
        return   /* descend: the fence marks take their faint from the highlighter */
      }
      if (name === "HorizontalRule") {
        if (!showRaw(n.from, n.to)) deco.push(Decoration.replace({widget: new HRW()}).range(n.from, n.to))
        return
      }
      if (name === "Table") { eachLine(n.from, n.to, "cm-mdtable"); return }
    }})
  }
  return Decoration.set(deco, true)
}

/* ---- the commands the bar and the keys share ---------------------- */
const findAbove = (state, pos, name) => {
  for (let n = syntaxTree(state).resolveInner(pos, -1); n; n = n.parent)
    if (n.name === name) return n
  return null
}
const inline = (marker, nodeName, markName) => view => {
  const {state} = view
  const r = state.selection.main
  const n = findAbove(state, r.from, nodeName) || findAbove(state, r.to, nodeName)
  if (n) {
    const ms = n.getChildren(markName)
    if (ms.length) {
      view.dispatch({changes: ms.map(m => ({from: m.from, to: m.to}))})
      view.focus()
      return true
    }
  }
  view.dispatch(state.changeByRange(rr => ({
    changes: [{from: rr.from, insert: marker}, {from: rr.to, insert: marker}],
    range: EditorSelection.range(rr.from + marker.length, rr.to + marker.length),
  })))
  view.focus()
  return true
}
const heading = view => {
  const {state} = view
  const r = state.selection.main
  const first = state.doc.lineAt(r.from)
  const cur = /^(#{1,6})\s/.exec(first.text)
  /* the title above the editor is the H1, so the cycle starts at ## */
  const next = !cur ? "## " : cur[1].length === 2 ? "### " : cur[1].length === 3 ? "#### " : ""
  const a = first.number, b = state.doc.lineAt(r.to).number
  const changes = []
  for (let i = a; i <= b; i++) {
    const l = state.doc.line(i)
    if (!l.text.trim() && a !== b) continue
    const m = /^(#{1,6})\s/.exec(l.text)
    changes.push({from: l.from, to: l.from + (m ? m[0].length : 0), insert: next})
  }
  if (changes.length) view.dispatch({changes})
  view.focus()
  return true
}
const STRIP = /^(?:>\s?|[-*+]\s\[[ xX]\]\s|[-*+]\s|\d+[.)]\s)/
const linePrefix = (test, make) => view => {
  const {state} = view
  const r = state.selection.main
  const a = state.doc.lineAt(r.from).number, b = state.doc.lineAt(r.to).number
  const lines = []
  for (let i = a; i <= b; i++) lines.push(state.doc.line(i))
  const used = lines.filter(l => l.text.trim())
  const on = used.length > 0 && used.every(l => test.test(l.text))
  const changes = []
  let k = 0
  lines.forEach(l => {
    if (!l.text.trim() && lines.length > 1) return
    if (on) {
      const m = test.exec(l.text)
      if (m) changes.push({from: l.from, to: l.from + m[0].length})
    } else {
      /* whatever block prefix is there makes way for the new one */
      const m = STRIP.exec(l.text)
      changes.push({from: l.from, to: l.from + (m ? m[0].length : 0), insert: make(k++)})
    }
  })
  if (changes.length) view.dispatch({changes})
  view.focus()
  return true
}
const link = view => {
  view.dispatch(view.state.changeByRange(r => r.empty
    ? {changes: {from: r.from, insert: "[]()"}, range: EditorSelection.cursor(r.from + 1)}
    : {changes: [{from: r.from, insert: "["}, {from: r.to, insert: "]()"}],
       range: EditorSelection.cursor(r.to + 3)}))
  view.focus()
  return true
}
const cmds = {
  bold: inline("**", "StrongEmphasis", "EmphasisMark"),
  italic: inline("*", "Emphasis", "EmphasisMark"),
  code: inline("`", "InlineCode", "CodeMark"),
  link,
  heading,
  quote: linePrefix(/^>\s?/, () => "> "),
  bullet: linePrefix(/^[-*+]\s(?!\[[ xX]\]\s)/, () => "- "),
  ordered: linePrefix(/^\d+[.)]\s/, i => (i + 1) + ". "),
  task: linePrefix(/^[-*+]\s\[[ xX]\]\s/, () => "- [ ] "),
}

/* the bar's buttons light up where the caret stands */
function activeStates(state) {
  const r = state.selection.main
  const s = {}
  for (let n = syntaxTree(state).resolveInner(r.from, -1); n; n = n.parent) {
    if (n.name === "StrongEmphasis") s.bold = true
    else if (n.name === "Emphasis") s.italic = true
    else if (n.name === "InlineCode") s.code = true
    else if (n.name === "Link") s.link = true
    else if (n.name === "Blockquote") s.quote = true
    else if (/^ATXHeading/.test(n.name)) s.heading = true
  }
  const lt = state.doc.lineAt(r.from).text
  if (/^[-*+]\s\[[ xX]\]\s/.test(lt)) s.task = true
  else if (/^[-*+]\s/.test(lt)) s.bullet = true
  else if (/^\d+[.)]\s/.test(lt)) s.ordered = true
  return s
}

/* ---- the hook ----------------------------------------------------- */
const impl = {
  mounted_core() {
    const seed = this.el.querySelector("textarea")
    const initial = seed ? seed.value : ""
    const readOnly = this.el.dataset.readonly === "true"
    this.el.replaceChildren()

    let debounce = null
    let lastPing = 0

    const pushText = text => {
      const now = Date.now()
      if (now - lastPing > 2000) {
        lastPing = now
        this.pushEvent("editor_activity", {})
      }
      clearTimeout(debounce)
      debounce = setTimeout(() => { debounce = null; this.pushEvent("body_changed", {text}) }, 300)
    }

    /* leaving the editor settles the debounce at once, so a click on
       Save version can never miss the last keystrokes. CodeMirror
       reports focus changes asynchronously, so the blur alone is not
       enough: the Save button's mousedown flushes synchronously,
       before the click's round trip. */
    const flushNow = () => {
      if (!debounce) return
      clearTimeout(debounce)
      debounce = null
      this.pushEvent("body_changed", {text: this.view.state.doc.toString()})
    }
    this.onDocMousedown = e => {
      if (e.target.closest("[phx-click='save_version'], [phx-click='publish']")) flushNow()
    }
    document.addEventListener("mousedown", this.onDocMousedown, true)

    /* an inline thumbnail's backdrop: same-origin upload paths load a
       scaled rendition, never the full original; remote addresses are
       drawn as they are */
    const resolveImage = url => {
      if (!/^(https?:|data:|blob:|\/)/.test(url)) return null
      /* a video has no thumbnail of its own here; the widget wears a
         play mark, and the panel below the text says where its
         conversion stands */
      if (VIDEO_FILE.test(url)) return null
      const scaled = url.startsWith("/uploads/")
        ? "/renditions/320/" + url.slice("/uploads/".length)
        : url
      return `url('${scaled.replace(/'/g, "%27")}')`
    }

    const livePreview = ViewPlugin.fromClass(class {
      constructor(view) { this.deco = buildDeco(view, resolveImage) }
      update(u) {
        if (u.docChanged || u.selectionSet || u.viewportChanged ||
            u.startState.readOnly !== u.state.readOnly) this.deco = buildDeco(u.view, resolveImage)
      }
    }, {decorations: v => v.deco})

    const roComp = new Compartment()
    const roExt = ro => [EditorState.readOnly.of(ro), EditorView.editable.of(!ro)]
    const fixed = [
      EditorView.lineWrapping,
      syntaxHighlighting(mdHighlight),
      livePreview,
      placeholder("Write. Markdown works: ## for a heading. Paste a picture or a video, or drop one here to put it in the text."),
      EditorView.contentAttributes.of({"aria-label": "Body, Markdown"}),
      keymap.of([
        {key: "Mod-b", run: cmds.bold},
        {key: "Mod-i", run: cmds.italic},
        {key: "Mod-k", run: cmds.link},
        {key: "Enter", run: insertNewlineContinueMarkup},
        {key: "Backspace", run: deleteMarkupBackward},
        ...historyKeymap,
        ...defaultKeymap,
      ]),
      EditorView.updateListener.of(u => {
        if (u.docChanged && !u.transactions.some(t => t.annotation(remoteChange)))
          pushText(u.state.doc.toString())
        if (u.focusChanged && !u.view.hasFocus) flushNow()
        if (u.docChanged || u.selectionSet) this.paintBar(activeStates(u.state))
      }),
      EditorView.domEventHandlers({
        paste: e => {
          const fs = [...((e.clipboardData && e.clipboardData.files) || [])].filter(f => /^(image|video)\//.test(f.type))
          if (!fs.length) return false
          e.preventDefault()
          this.uploadFiles(fs)
          return true
        },
        drop: (e, v) => {
          const fs = [...((e.dataTransfer && e.dataTransfer.files) || [])].filter(f => /^(image|video)\//.test(f.type))
          if (!fs.length) return false
          e.preventDefault()   /* the outer dropzone sees this and stands down */
          if (v.state.readOnly) { this.pushEvent("ask_takeover", {}); return true }
          const pos = v.posAtCoords({x: e.clientX, y: e.clientY})
          if (pos != null) v.dispatch({selection: {anchor: pos}})
          v.focus()
          this.uploadFiles(fs)
          return true
        },
      }),
    ]
    const mkState = (text, ro) => EditorState.create({
      doc: text,
      extensions: [history(), roComp.of(roExt(ro)), markdown({base: markdownLanguage}), fixed],
    })
    this.view = new EditorView({parent: this.el, state: mkState(initial, readOnly)})

    /* the read-only body is not focusable, so the takeover ask hangs
       on the pointer. On click, not mousedown: a dialog opened during
       mousedown would catch the very click that opened it on its own
       scrim and close again before the hand leaves the mouse. */
    this.el.addEventListener("click", () => {
      if (this.view.state.readOnly) this.pushEvent("ask_takeover", {})
    })

    /* the formatting bar: mousedown is swallowed so the caret never
       leaves the text, and the click runs the same command the
       keyboard would. In the read-only state the command asks for the
       takeover instead. */
    const bar = document.getElementById("mdBar")
    if (bar) {
      bar.addEventListener("mousedown", e => { if (e.target.closest(".mdb")) e.preventDefault() })
      bar.addEventListener("click", e => {
        const b = e.target.closest(".mdb")
        if (b) this.cmd(b.dataset.cmd)
      })
    }

    this.handleEvent("sync_body", ({text, caret}) => this.sync(text, caret))
    /* the takeover's flush: whatever still sits in the debounce goes
       to the server right now */
    this.handleEvent("flush_body", () => {
      clearTimeout(debounce)
      debounce = null
      this.pushEvent("body_flushed", {text: this.view.state.doc.toString()})
    })
    this.handleEvent("set_readonly", ({readOnly: ro}) => {
      this.view.dispatch({effects: roComp.reconfigure(roExt(ro))})
      if (ro && this.view.hasFocus) this.view.contentDOM.blur()
    })

    this.mountUploads()
  },

  /* ---- images into the body, the GitHub way ------------------------
     A token holds the caret's place while the file travels; the token
     becomes the reference on success and a failure marker on error.
     The panel under the text is server-rendered from the body; its
     Retry / Remove / Cancel buttons land here, because the file and
     the running request live only in this browser. */
  mountUploads() {
    this.uploads = new Map()   /* name → {file, xhr} */
    this.queue = []
    this.running = 0

    const wrap = this.el.closest("#bodyWrap")
    const flag = document.getElementById("bodyDropFlag")
    const carriesFiles = dt => !!dt && [...(dt.types || [])].indexOf("Files") >= 0
    const show = on => {
      if (wrap) wrap.classList.toggle("body-drop", on)
      if (flag) flag.hidden = !on
    }
    if (wrap) {
      ;["dragenter", "dragover"].forEach(ev => wrap.addEventListener(ev, e => {
        if (!carriesFiles(e.dataTransfer)) return
        e.preventDefault()
        e.dataTransfer.dropEffect = "copy"
        show(true)
      }))
      wrap.addEventListener("dragleave", e => {
        if (!e.relatedTarget || !wrap.contains(e.relatedTarget)) show(false)
      })
      wrap.addEventListener("drop", e => {
        show(false)
        if (e.defaultPrevented) return   /* the editor already took it */
        if (!carriesFiles(e.dataTransfer)) return
        e.preventDefault()
        const files = [...e.dataTransfer.files].filter(f => /^(image|video)\//.test(f.type))
        if (!files.length) return
        this.view.focus()
        this.uploadFiles(files)
      })
    }

    const picker = document.getElementById("mdImgFile")
    if (picker) {
      picker.addEventListener("change", () => {
        const files = [...picker.files].filter(f => /^(image|video)\//.test(f.type))
        picker.value = ""
        if (!files.length) return
        this.view.focus()
        this.uploadFiles(files)
      })
    }

    this.onPanelClick = e => {
      const b = e.target.closest("[data-img-action]")
      if (!b) return
      const name = b.dataset.imgFile
      const action = b.dataset.imgAction
      if (action === "retry") this.retryUpload(name)
      else this.removeUpload(name, action)
    }
    document.addEventListener("click", this.onPanelClick)
  },

  upToken(name) { return "![Uploading " + name + "…]()" },
  failToken(name) { return "![Upload failed: " + name + "]()" },
  doneRef(name, url) { return "![" + name.replace(/\.\w+$/, "") + "](" + url + ")" },

  uploadFiles(files) {
    if (this.view.state.readOnly) { this.pushEvent("ask_takeover", {}); return }
    const doc = this.view.state.doc.toString()
    const used = new Set([...this.uploads.keys()])
    for (const m of doc.matchAll(/!\[(?:Uploading (.+?)…|Upload failed: (.+?))\]\(\)/g))
      used.add(m[1] || m[2])
    for (const m of doc.matchAll(/!\[[^\]]*\]\(([^)]+)\)/g))
      used.add(m[1].trim().split("/").pop())

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
      this.uploads.set(name, {file: f, xhr: null})
      return name
    })

    this.insertText(names.map(n => this.upToken(n)).join("\n\n"))
    this.pushEvent("images_inserted", {files: names})
    names.forEach(n => this.queue.push(n))
    this.pump()
  },

  pump() {
    while (this.running < 2 && this.queue.length) {
      const name = this.queue.shift()
      if (this.uploads.has(name)) this.startUpload(name)
    }
  },

  startUpload(name) {
    const entry = this.uploads.get(name)
    this.running++
    const xhr = new XMLHttpRequest()
    entry.xhr = xhr
    xhr.open("POST", "/admin/images")
    const meta = document.querySelector("meta[name='csrf-token']")
    if (meta) xhr.setRequestHeader("x-csrf-token", meta.getAttribute("content"))
    let pct = 0
    xhr.upload.addEventListener("progress", e => {
      if (!e.lengthComputable) return
      pct = Math.round((e.loaded / e.total) * 100)
      this.pushEvent("upload_progress", {file: name, pct})
    })
    const settle = () => { this.running--; this.pump() }
    xhr.addEventListener("load", () => {
      settle()
      if (xhr.status === 200) {
        const {url} = JSON.parse(xhr.responseText)
        this.swap(this.upToken(name), this.doneRef(name, url))
        this.uploads.delete(name)
        this.pushEvent("image_uploaded", {file: name})
      } else {
        this.swap(this.upToken(name), this.failToken(name))
        this.pushEvent("image_failed", {file: name, pct})
      }
    })
    xhr.addEventListener("error", () => {
      settle()
      this.swap(this.upToken(name), this.failToken(name))
      this.pushEvent("image_failed", {file: name, pct})
    })
    const form = new FormData()
    form.append("file", entry.file, name)
    xhr.send(form)
  },

  retryUpload(name) {
    if (this.view.state.readOnly) { this.pushEvent("ask_takeover", {}); return }
    const entry = this.uploads.get(name)
    if (!entry || !entry.file) {
      /* the browser that held the file is gone (a reload, the other
         side): nothing to send again */
      this.pushEvent("image_retry_missing", {file: name})
      return
    }
    this.swap(this.failToken(name), this.upToken(name))
    this.pushEvent("image_retry", {file: name})
    this.queue.push(name)
    this.pump()
  },

  removeUpload(name, how) {
    if (this.view.state.readOnly) { this.pushEvent("ask_takeover", {}); return }
    const entry = this.uploads.get(name)
    if (entry && entry.xhr) { try { entry.xhr.abort() } catch (_e) {} }
    this.uploads.delete(name)
    const raw = how === "cancel" ? this.upToken(name) : this.failToken(name)
    if (!this.swap(raw + "\n\n", "")) this.swap(raw, "")
    this.pushEvent("image_removed", {file: name, how})
  },

  /* writing into the body without losing the caret: the token lands at
     the caret with clean blank lines around it */
  insertText(text) {
    const view = this.view
    const r = view.state.selection.main
    const doc = view.state.doc.toString()
    const before = doc.slice(0, r.from)
    const after = doc.slice(r.to)
    const lead = !before ? "" : /\n\n$/.test(before) ? "" : /\n$/.test(before) ? "\n" : "\n\n"
    const tail = !after ? "" : /^\n\n/.test(after) ? "" : /^\n/.test(after) ? "\n" : "\n\n"
    const ins = lead + text + tail
    view.dispatch({
      changes: {from: r.from, to: r.to, insert: ins},
      selection: {anchor: r.from + ins.length},
    })
  },

  swap(from, to) {
    const doc = this.view.state.doc.toString()
    const at = doc.indexOf(from)
    if (at < 0) return false
    this.view.dispatch({changes: {from: at, to: at + from.length, insert: to}})
    return true
  },

  destroyed_core() {
    if (this.view) this.view.destroy()
    if (this.onDocMousedown) document.removeEventListener("mousedown", this.onDocMousedown, true)
    if (this.onPanelClick) document.removeEventListener("click", this.onPanelClick)
    if (this.uploads) {
      for (const entry of this.uploads.values()) {
        if (entry.xhr) { try { entry.xhr.abort() } catch (_e) {} }
      }
    }
  },

  /* the model changed around the editor: the smallest change that gets
     there, so everything around it, the caret included, maps through
     instead of resetting */
  sync(text, caretTo) {
    const view = this.view
    const cur = view.state.doc.toString()
    if (cur === text) {
      if (caretTo != null) view.dispatch({selection: {anchor: Math.min(caretTo, text.length)}})
      return
    }
    let a = 0, b = cur.length, b2 = text.length
    while (a < b && a < b2 && cur.charCodeAt(a) === text.charCodeAt(a)) a++
    while (b > a && b2 > a && cur.charCodeAt(b - 1) === text.charCodeAt(b2 - 1)) { b--; b2-- }
    view.dispatch({
      changes: {from: a, to: b, insert: text.slice(a, b2)},
      selection: caretTo != null ? {anchor: Math.min(caretTo, text.length)} : undefined,
      annotations: remoteChange.of(true),
    })
  },

  cmd(name) {
    if (this.view.state.readOnly) { this.pushEvent("ask_takeover", {}); return }
    if (name === "image") {
      const picker = document.getElementById("mdImgFile")
      if (picker) picker.click()
      return
    }
    const c = cmds[name]
    if (c) c(this.view)
  },

  paintBar(states) {
    document.querySelectorAll("#mdBar .mdb").forEach(b =>
      b.classList.toggle("on", !!states[b.dataset.cmd]))
  },
}

export function mount(hook) {
  Object.assign(hook, impl)
  hook.mounted_core()
}
