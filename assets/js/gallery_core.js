/* The tiles block's client half, ported from round-14 with the touch
   mechanics the imaedge proof settled on.

   in:  the server tiles in #tileServer (truth, re-rendered on every
        gallery_changed), gallery_moved {id, note} when somebody else
        sorted
   out: gallery_reorder {id, ids}, gallery_set_date {id, date},
        gallery_undo {id}, gallery_refresh - and files as one POST per
        file to the upload url

   The hook owns three things LiveView must not touch: the local
   upload tiles in #tileLocal (phx-update="ignore"), the lightbox it
   appends to <body>, and the undo bar. While a tile is held, the hook
   puts phx-update="ignore" on #tileServer itself - the patcher reads
   that attribute from the live DOM, so the grid freezes under the
   hand; the drop takes it off again and asks for gallery_refresh,
   whose rev bump guarantees a diff that morphs the whole grid back
   to the server's truth. */

import {t, esc} from "./i18n"

const MAX_PARALLEL = 2
const MAX_FILE_MB = 50
/* a film off a phone weighs what a photograph never does; the roof for
   a video stands where the parser's does (see endpoint.ex) */
const MAX_VIDEO_MB = 500
const TOUCH_DRAG_DELAY_MS = 200
const DRAG_THRESHOLD_PX = 9
const TAP_MS = 500
const SWIPE_THRESHOLD_PX = 48
const SCROLL_EDGE_PX = 64
const SCROLL_STEP_PX = 14
const NOTE_MS = 2600
const JMOVE_MS = 2600
const UNDO_S = 10
const SAVED_MS = 4000

const FOCUSABLE = "a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex='-1'])"

export function mount(hook) {
  const core = new Gallery(hook)
  hook.updated_core = () => core.updated()
  hook.destroyed_core = () => core.destroy()
}

class Gallery {
  constructor(hook) {
    this.hook = hook
    this.el = hook.el
    this.uploadUrl = this.el.dataset.uploadUrl
    this.csrf = this.el.dataset.csrf

    this.grid = this.el.querySelector("#tileGrid")
    this.server = this.el.querySelector("#tileServer")
    this.local = this.el.querySelector("#tileLocal")
    this.note = this.el.querySelector("#tileNote")
    this.onWay = this.el.querySelector("#tileOnWay")
    this.dropFlag = this.el.querySelector("#tileDropFlag")

    this.records = []
    this.active = 0
    this.uid = 0
    this.drag = null
    this.lb = null
    this.renderQueued = false

    this.mountAdd()
    this.mountDropzone()
    this.mountSort()
    this.mountLocalActions()
    this.mountTileActions()

    this.onKeydown = e => this.keydown(e)
    window.addEventListener("keydown", this.onKeydown)

    hook.handleEvent("gallery_moved", ({id, note}) => {
      const tile = this.server.querySelector(`[data-id="${id}"]`)
      if (tile) {
        tile.classList.add("jmove")
        setTimeout(() => tile.classList.remove("jmove"), JMOVE_MS)
      }
      this.noteTile(note)
    })
  }

  destroy() {
    this.records.forEach(r => {
      if (r.xhr) r.xhr.abort()
      if (r.objurl) URL.revokeObjectURL(r.objurl)
    })
    window.removeEventListener("keydown", this.onKeydown)
    this.releasePan()
    this.closeLightbox(true)
    this.removeUndoBar()
  }

  // after every LiveView patch: settle finished uploads, follow the
  // lightbox's image through renames, deletes and re-sorts
  updated() {
    this.settleDone()
    this.refreshLightbox()
  }

  tiles() {
    return [...this.server.querySelectorAll("[data-id]")]
  }

  currentIds() {
    return this.tiles().map(t => t.dataset.id)
  }

  /* ================= the note line ================= */

  noteTile(text) {
    if (!this.note) return
    clearTimeout(this.noteTimer)
    this.note.textContent = text
    this.note.classList.add("text-julia", "font-semibold")
    /* the line has nothing to say the rest of the time, and an empty
       one is not drawn at all: the rule stands over the grid */
    this.noteTimer = setTimeout(() => {
      this.note.textContent = ""
      this.note.classList.remove("text-julia", "font-semibold")
    }, NOTE_MS)
  }

  /* ================= the upload queue ================= */

  mountAdd() {
    const files = this.el.querySelector("#tileFiles")
    this.el.querySelector("#tileAdd").addEventListener("click", () => files.click())
    files.addEventListener("change", () => {
      this.addFiles(files.files)
      files.value = ""
    })
  }

  mountDropzone() {
    let depth = 0
    const hasFiles = e => e.dataTransfer && [...e.dataTransfer.types].includes("Files")

    this.grid.addEventListener("dragenter", e => {
      if (!hasFiles(e)) return
      e.preventDefault()
      depth += 1
      this.grid.classList.add("grid-drop")
      this.dropFlag.hidden = false
    })
    this.grid.addEventListener("dragover", e => {
      if (hasFiles(e)) e.preventDefault()
    })
    this.grid.addEventListener("dragleave", e => {
      if (!hasFiles(e)) return
      depth = Math.max(0, depth - 1)
      if (depth === 0) {
        this.grid.classList.remove("grid-drop")
        this.dropFlag.hidden = true
      }
    })
    this.grid.addEventListener("drop", e => {
      if (!hasFiles(e)) return
      e.preventDefault()
      depth = 0
      this.grid.classList.remove("grid-drop")
      this.dropFlag.hidden = true
      this.addFiles(e.dataTransfer.files)
    })
  }

  addFiles(fileList) {
    /* pictures and videos alike; a video is converted on the server
       after the upload, and its tile waits for the poster */
    const images = [...fileList].filter(f => /^(image|video)\//.test(f.type))
    for (const file of images) {
      // an oversize file fails right here instead of after minutes of upload
      const roof = /^video\//.test(file.type) ? MAX_VIDEO_MB : MAX_FILE_MB
      const oversize = file.size > roof * 1024 * 1024

      this.records.push({
        id: "u" + ++this.uid,
        file,
        name: file.name,
        /* only a picture can stand in for itself while it travels; a
           video shows its name and its state until the server has a
           poster for it */
        objurl: /^image\//.test(file.type) ? URL.createObjectURL(file) : null,
        status: oversize ? "failed" : "queued",
        error: oversize ? t("bigger than the %{roof} MB roof", {roof}) : null,
        noRetry: oversize,
        pct: 0,
      })

      if (oversize)
        this.noteTile(t("%{name} is bigger than the %{roof} MB roof.", {name: file.name, roof}))
    }
    if (images.length) {
      this.renderLocal()
      this.pump()
    }
  }

  pump() {
    while (this.active < MAX_PARALLEL) {
      const next = this.records.find(r => r.status === "queued")
      if (!next) break
      this.upload(next)
    }
  }

  upload(record) {
    this.active += 1
    record.status = "uploading"
    record.pct = 0

    const xhr = new XMLHttpRequest()
    record.xhr = xhr
    xhr.open("POST", this.uploadUrl)
    xhr.setRequestHeader("x-csrf-token", this.csrf)
    xhr.responseType = "json"

    xhr.upload.onprogress = e => {
      if (e.lengthComputable) {
        record.pct = Math.min(99, Math.round((e.loaded / e.total) * 100))
        this.scheduleRender()
      }
    }
    // bytes are out the door; the server is reading the picture now
    xhr.upload.onload = () => {
      record.status = "processing"
      this.scheduleRender()
    }
    xhr.onload = () => {
      this.active -= 1
      record.xhr = null
      if (xhr.status === 200 && xhr.response && xhr.response.id != null) {
        record.serverId = String(xhr.response.id)
        record.done = true
        this.settleDone()
      } else {
        record.status = "failed"
        record.error = (xhr.response && xhr.response.error) || t("upload failed")
        this.noteTile(t("%{name} failed to upload. Retry or remove it.", {name: record.name}))
      }
      this.scheduleRender()
      this.pump()
    }
    xhr.onerror = xhr.ontimeout = () => {
      this.active -= 1
      record.xhr = null
      record.status = "failed"
      record.error = t("upload failed")
      this.noteTile(`${record.name} failed to upload. Retry or remove it.`)
      this.scheduleRender()
      this.pump()
    }
    // abort fires neither load nor error; without this the slot would
    // stay taken and the cancelled tile could never leave
    xhr.onabort = () => {
      this.active -= 1
      record.xhr = null
      this.dropRecord(record)
      this.pump()
    }

    const form = new FormData()
    form.append("file", record.file, record.name)
    xhr.send(form)
    this.scheduleRender()
  }

  // a finished upload's local tile leaves the moment the server tile
  // is really in the grid, so the picture never blinks out in between
  settleDone() {
    let dropped = false
    this.records = this.records.filter(r => {
      if (r.done && this.server.querySelector(`[data-id="${r.serverId}"]`)) {
        URL.revokeObjectURL(r.objurl)
        dropped = true
        return false
      }
      return true
    })
    if (dropped) this.renderLocal()
  }

  mountLocalActions() {
    this.local.addEventListener("click", e => {
      const button = e.target.closest("button[data-act]")
      if (!button) return
      e.stopPropagation()
      const record = this.records.find(r => r.id === button.closest("[data-local-id]").dataset.localId)
      if (!record) return

      if (button.dataset.act === "cancel" || button.dataset.act === "remove") {
        if (record.xhr) record.xhr.abort()
        else this.dropRecord(record)
      } else if (button.dataset.act === "retry") {
        record.status = "queued"
        record.pct = 0
        this.renderLocal()
        this.pump()
      }
    })
  }

  // the delete button on a finished tile: gone at once, undo below
  mountTileActions() {
    this.grid.addEventListener("click", e => {
      const del = e.target.closest("button[data-del]")
      if (!del) return
      e.stopPropagation()
      const tile = del.closest("[data-id]")
      if (!tile) return
      this.hook.pushEvent("gallery_delete", {id: tile.dataset.id})
      this.showUndoBar(tile.dataset.id, tile.dataset.filename)
    })
  }

  dropRecord(record) {
    URL.revokeObjectURL(record.objurl)
    this.records = this.records.filter(r => r !== record)
    this.renderLocal()
  }

  scheduleRender() {
    if (this.renderQueued) return
    this.renderQueued = true
    requestAnimationFrame(() => {
      this.renderQueued = false
      this.renderLocal()
    })
  }

  renderLocal() {
    const html = this.records
      .filter(r => !r.done)
      .map(r => this.localTile(r))
      .join("")
    this.local.innerHTML = html

    const away = this.records.filter(r => !r.done && r.status !== "failed").length
    this.onWay.textContent = away ? ` · ${t("%{count} on the way", {count: away})}` : ""
  }

  // What a travelling tile says about itself, in words. The screen
  // reader gets the same sentence as the eye, so it is built once.
  statusWord(r) {
    return r.status === "queued" ? t("queued")
      : r.status === "uploading" ? t("uploading %{pct}%", {pct: r.pct})
      : r.status === "processing" ? t("processing")
      : r.error || t("upload failed")
  }

  localTile(r) {
    const word = this.statusWord(r)
    const st =
      r.status === "processing"
        ? `<i class="spin inline-block w-[8px] h-[8px] rounded-full border border-white border-t-transparent"></i>${esc(word)}`
        : esc(word)

    const bar =
      r.status === "failed"
        ? ""
        : `<span class="tile-bar"><i style="width:${r.status === "queued" ? 0 : r.status === "processing" ? 100 : r.pct}%"></i></span>`

    const buttons =
      r.status === "failed"
        ? (r.noRetry ? "" : `<button type="button" class="tile-x" data-act="retry">${esc(t("Retry"))}</button>`) +
          `<button type="button" class="tile-x" data-act="remove">${esc(t("Remove"))}</button>`
        : `<button type="button" class="tile-x" data-act="cancel">${esc(t("Cancel"))}</button>`

    return `<div class="tile up ${r.status}" data-local-id="${r.id}"
      ${r.objurl ? `style="background-image:url('${r.objurl}')"` : ""}
      aria-label="${esc(r.name)}, ${esc(word)}">
      <span class="tile-ov">
        <span class="fn" title="${esc(r.name)}">${esc(r.name)}</span>
        <span class="st">${st}</span>
        ${bar}
        <span class="flex gap-[4px] mt-[2px]">${buttons}</span>
      </span>
    </div>`
  }

  /* ================= drag to sort ================= */

  // The scroll container behind the tiles: the side column where it
  // scrolls alone (lg and up), the page below that.
  scroller() {
    const side = document.getElementById("sideCol")
    if (side && getComputedStyle(side).overflowY === "auto" && side.scrollHeight > side.clientHeight) {
      return side
    }
    return window
  }

  mountSort() {
    this.grid.addEventListener("pointerdown", e => this.pointerDown(e))
    this.grid.addEventListener("pointermove", e => this.pointerMove(e))
    this.grid.addEventListener("pointerup", e => this.pointerUp(e))
    this.grid.addEventListener("pointercancel", e => this.pointerUp(e))

    // keyboard: a tile is a button; Enter and Space open it big
    this.grid.addEventListener("keydown", e => {
      if (e.key !== "Enter" && e.key !== " ") return
      const tile = e.target.closest && e.target.closest("[data-id]")
      if (!tile) return
      e.preventDefault()
      this.openLightbox(tile.dataset.id)
    })
  }

  pointerDown(e) {
    if (!e.isPrimary || this.drag) return
    if (e.target.closest("button")) return
    const tile = e.target.closest(".tile")
    if (!tile || tile.classList.contains("up") || !this.server.contains(tile)) return

    this.drag = {
      tile,
      id: tile.dataset.id,
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      lastY: e.clientY,
      downAt: performance.now(),
      held: false,
      moved: false,
      mode: null,
      timer: null,
    }
    tile.setPointerCapture(e.pointerId)

    if (e.pointerType === "mouse") {
      e.preventDefault()
      this.lift()
    } else {
      this.drag.timer = setTimeout(() => this.lift(), TOUCH_DRAG_DELAY_MS)
    }
  }

  lift() {
    const d = this.drag
    if (!d || d.held) return
    d.held = true
    d.initialOrder = this.currentIds()
    d.tile.classList.add("lift", "slot")
    this.server.setAttribute("phx-update", "ignore")
    if (navigator.vibrate) navigator.vibrate(8)
    this.holdPan()
  }

  // The tiles allow a vertical pan, so the browser scrolls them itself
  // and does it smoothly. Once a press becomes a sort, the pan has to
  // stop: it has not started yet (the finger stood still through the
  // whole delay), and a refused touchmove keeps it from starting.
  //
  // A hold that outlived its drag would leave the page unscrollable, so
  // the last touch of any hand releases it as well - pointerup is the
  // rule, this is the floor under it.
  holdPan() {
    if (this.panHold) return
    this.panHold = e => e.preventDefault()
    this.panEnd = () => this.releasePan()
    document.addEventListener("touchmove", this.panHold, {passive: false})
    document.addEventListener("touchend", this.panEnd)
    document.addEventListener("touchcancel", this.panEnd)
  }

  releasePan() {
    if (!this.panHold) return
    document.removeEventListener("touchmove", this.panHold, {passive: false})
    document.removeEventListener("touchend", this.panEnd)
    document.removeEventListener("touchcancel", this.panEnd)
    this.panHold = null
    this.panEnd = null
  }

  pointerMove(e) {
    const d = this.drag
    if (!d || e.pointerId !== d.pointerId) return

    const dx = e.clientX - d.startX
    const dy = e.clientY - d.startY
    const distance = Math.hypot(dx, dy)

    // A finger going sideways means sorting; going down the page it
    // means reading, and that gesture belongs to the browser, which
    // ends this one with a pointercancel.
    if (!d.held && !d.mode && distance > DRAG_THRESHOLD_PX) {
      clearTimeout(d.timer)
      if (e.pointerType === "mouse" || Math.abs(dx) >= Math.abs(dy)) {
        this.lift()
      } else {
        d.mode = "scroll"
      }
    }

    if (d.held) {
      if (distance > DRAG_THRESHOLD_PX) d.moved = true
      this.place(e.clientX, e.clientY)
      this.autoScroll(e.clientY)
    }

    d.lastY = e.clientY
  }

  place(x, y) {
    const under = document.elementFromPoint(x, y)
    const target = under && under.closest("[data-id]")
    const d = this.drag
    if (!target || target === d.tile || !this.server.contains(target)) return

    const rect = target.getBoundingClientRect()
    const nearSameRow = Math.abs(y - (rect.top + rect.height / 2)) < rect.height * 0.35
    const after = nearSameRow ? x > rect.left + rect.width / 2 : y > rect.top + rect.height / 2

    this.flip(() => {
      this.server.insertBefore(d.tile, after ? target.nextSibling : target)
    })
    this.renumber()
  }

  flip(mutate) {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return mutate()

    const before = new Map(this.tiles().map(t => [t, t.getBoundingClientRect()]))
    mutate()
    for (const tile of this.tiles()) {
      const from = before.get(tile)
      if (!from) continue
      const to = tile.getBoundingClientRect()
      const dx = from.left - to.left
      const dy = from.top - to.top
      if (dx || dy) {
        tile.animate(
          [{transform: `translate(${dx}px, ${dy}px)`}, {transform: "translate(0, 0)"}],
          {duration: 180, easing: "cubic-bezier(.2,.7,.3,1)"}
        )
      }
    }
  }

  renumber() {
    this.tiles().forEach((tile, index) => {
      const n = tile.querySelector(".n")
      if (n) n.textContent = String(index + 1).padStart(2, "0")
    })
  }

  autoScroll(clientY) {
    if (clientY < SCROLL_EDGE_PX) {
      this.scroller().scrollBy(0, -SCROLL_STEP_PX)
    } else if (clientY > window.innerHeight - SCROLL_EDGE_PX) {
      this.scroller().scrollBy(0, SCROLL_STEP_PX)
    }
  }

  pointerUp(e) {
    const d = this.drag
    if (!d || e.pointerId !== d.pointerId) return
    clearTimeout(d.timer)
    this.releasePan()
    this.drag = null

    if (d.held) {
      d.tile.classList.remove("lift", "slot")
      this.server.removeAttribute("phx-update")

      const ids = this.currentIds()
      if (d.moved && ids.join("\n") !== d.initialOrder.join("\n")) {
        this.hook.pushEvent("gallery_reorder", {id: d.id, ids})
      }
      // whatever the freeze held off, and whatever the hand moved
      // without committing: one refresh morphs the grid back to truth
      this.hook.pushEvent("gallery_refresh", {})

      if (!d.moved && e.type === "pointerup" && performance.now() - d.downAt < TAP_MS) {
        this.openLightbox(d.id)
      }
    } else if (
      !d.mode &&
      e.type === "pointerup" &&
      performance.now() - d.downAt < TAP_MS
    ) {
      this.openLightbox(d.id)
    }
  }

  /* ================= the lightbox ================= */

  /* the tiles the lightbox can show. A video ffmpeg has not finished
     has no picture and no film yet, so it stays out of the paging;
     the sorting list above keeps every tile. */
  shownTiles() {
    return this.tiles().filter(t => t.dataset.full)
  }

  tileData(id) {
    const list = this.shownTiles()
    const index = list.findIndex(t => t.dataset.id === id)
    if (index < 0) return null
    const t = list[index]
    return {
      id,
      index,
      count: list.length,
      filename: t.dataset.filename,
      date: t.dataset.date,
      full: t.dataset.full,
      video: t.dataset.video,
      original: t.dataset.original,
    }
  }

  openLightbox(id) {
    const data = this.tileData(id)
    // a video that ffmpeg has not finished has nothing to show yet
    if (!data || !data.full || this.lb) return

    this.lb = {
      id,
      lastIndex: data.index,
      token: 0,
      formFor: null,
      paintedUrl: null,
      /* only the tile that was tapped starts playing by itself;
         paging past a film must not start it */
      opening: true,
      prevFocus: document.activeElement,
    }
    this.buildLightbox()
    document.body.style.overflow = "hidden"
    document.body.classList.add("has-overlay")
    this.paint()
    this.root.focus()
  }

  buildLightbox() {
    // a native dialog in the top layer: no z-index and no compositing
    // quirk (the topbar's backdrop-filter) can ever paint above it
    const root = document.createElement("dialog")
    root.id = "lbRoot"
    root.className = "lb-root"
    root.setAttribute("aria-label", t("Full size"))
    // the dialog itself takes the focus: autofocusing the date field
    // would pop a picker over the picture on a phone
    root.tabIndex = -1

    // aria-label on the delete button: its name stays whole for a
    // screen reader whatever the width, only the eye sees the short
    // word on a phone
    root.innerHTML = `
      <div class="lb-bar-a">
        <span id="lbCount" class="num"></span>
        <span class="sp"></span>
        <button type="button" id="lbDelete" class="lb-abtn danger" aria-label="${esc(t("Delete tile"))}"><span class="lb-word">${esc(t("Delete tile"))}</span><span class="lb-word-s">${esc(t("Delete"))}</span></button>
        <a id="lbOrig" class="lb-abtn plain" target="_blank" rel="noopener"><span class="lb-word">${esc(t("Open original"))}</span><span class="lb-word-s">${esc(t("Original"))}</span></a>
        <button type="button" id="lbClose" class="lb-abtn" aria-label="${esc(t("Close"))}">${esc(t("Close"))}</button>
      </div>
      <div id="lbStage" class="relative flex-1 min-h-0 flex items-center justify-center px-2 gap-2" style="touch-action:pan-y">
        <button type="button" class="lb-nav text-white/70 hover:text-white text-[30px] leading-none px-3 py-6 flex-none"
           data-nav="-1" aria-label="${esc(t("Previous tile"))}">&#8249;</button>
        <div class="relative flex-1 h-full min-w-0 flex items-center justify-center">
          <div id="lbImg" class="w-full h-full bg-center bg-contain bg-no-repeat" role="img" aria-label=""></div>
          <div id="lbState" class="absolute inset-0 grid place-items-center text-white/80 text-[13px] text-center px-6" hidden></div>
        </div>
        <button type="button" class="lb-nav text-white/70 hover:text-white text-[30px] leading-none px-3 py-6 flex-none"
           data-nav="1" aria-label="${esc(t("Next tile"))}">&#8250;</button>
      </div>
      <div id="lbFoot" class="flex-none bg-paper border-t border-rule px-4 py-3">
        <div class="max-w-[900px] mx-auto">
          <p class="text-[13px]"><b id="lbName"></b> <span class="note" id="lbMeta"></span></p>
          <div class="flex flex-wrap items-end gap-x-3 gap-y-2 mt-2">
            <span class="min-w-[220px]">
              <label class="lab block mb-[3px]" for="lbDate">${esc(t("Date"))}</label>
              <input type="datetime-local" id="lbDate" step="60">
            </span>
            <span class="note pb-[6px]" id="lbSaved">${esc(t("The date saves itself and sorts the gallery."))}</span>
          </div>
        </div>
      </div>`

    document.body.appendChild(root)
    this.root = root
    root.showModal()

    // Escape reaches the dialog as a cancel; closing stays one path
    root.addEventListener("cancel", e => {
      e.preventDefault()
      this.closeLightbox()
    })
    root.querySelector("#lbClose").addEventListener("click", () => this.closeLightbox())
    root.querySelectorAll("[data-nav]").forEach(b =>
      b.addEventListener("click", () => this.nav(parseInt(b.dataset.nav, 10)))
    )
    root.querySelector("#lbDelete").addEventListener("click", () => this.deleteCurrent())

    const date = root.querySelector("#lbDate")
    date.addEventListener("change", () => {
      const id = this.lb && this.lb.id
      if (!id || !date.value) return
      this.hook.pushEvent("gallery_set_date", {id, date: date.value}, reply => {
        if (reply.ok) {
          this.savedNote(null)
        } else {
          const data = this.tileData(id)
          if (data) date.value = data.date
          this.savedNote(t("That date could not be read"))
        }
      })
    })

    // swipe on the stage: fingers only, mostly horizontal
    const stage = root.querySelector("#lbStage")
    let swipe = null
    stage.addEventListener("pointerdown", e => {
      if (e.pointerType !== "mouse") swipe = {x: e.clientX, y: e.clientY}
    })
    stage.addEventListener("pointerup", e => {
      if (!swipe) return
      const dx = e.clientX - swipe.x
      const dy = e.clientY - swipe.y
      swipe = null
      if (Math.abs(dx) > SWIPE_THRESHOLD_PX && Math.abs(dx) > Math.abs(dy)) {
        this.nav(dx < 0 ? 1 : -1)
      }
    })
  }

  paint() {
    const lb = this.lb
    const data = this.tileData(lb.id)
    if (!data) return

    lb.lastIndex = data.index
    this.root.querySelector("#lbCount").textContent = `${data.index + 1} / ${data.count}`
    const orig = this.root.querySelector("#lbOrig")
    orig.href = data.original
    orig.setAttribute("download", data.filename)
    this.root.querySelector("#lbName").textContent = data.filename

    this.root.querySelector("#lbMeta").textContent =
      " · " +
      t("%{date} · %{index} of %{count}", {
        date: data.date.slice(0, 10),
        index: data.index + 1,
        count: data.count,
      })

    // never write over what somebody is typing right now
    if (lb.formFor !== lb.id) {
      this.root.querySelector("#lbDate").value = data.date
      lb.formFor = lb.id
    }

    // a paint from a background update must not restart a load that is
    // already on its way: on a slow line the picture would never land
    if (lb.paintedUrl !== data.full && lb.loadingUrl !== data.full) {
      if (data.video) this.loadVideo(data)
      else this.loadImage(data)
    }
  }

  // whatever was playing here stops before the next thing is painted
  stopFilm(stage) {
    const film = stage.querySelector("video")
    if (film) film.pause()
  }

  // a film plays where the picture would be, with the poster behind it
  // until the first frame arrives
  loadVideo(data) {
    const lb = this.lb
    lb.token += 1
    lb.loadingUrl = null
    lb.paintedUrl = data.full
    const img = this.root.querySelector("#lbImg")
    const state = this.root.querySelector("#lbState")

    state.hidden = true
    img.style.backgroundImage = ""
    this.stopFilm(img)

    const film = document.createElement("video")
    film.className = "lb-film"
    film.controls = true
    film.playsInline = true
    film.preload = lb.opening ? "metadata" : "none"
    film.poster = data.full
    film.src = data.video
    film.setAttribute("aria-label", data.filename)
    img.replaceChildren(film)
    if (lb.opening) film.play().catch(() => {})
    lb.opening = false
  }

  loadImage(data, bust) {
    const lb = this.lb
    const token = ++lb.token
    lb.loadingUrl = data.full
    const img = this.root.querySelector("#lbImg")
    const state = this.root.querySelector("#lbState")

    this.stopFilm(img)
    img.replaceChildren()
    img.style.backgroundImage = ""
    img.setAttribute("aria-label", data.filename)
    state.hidden = false
    state.textContent = t("Loading the full size…")

    const url = bust ? `${data.full}${data.full.includes("?") ? "&" : "?"}r=${Date.now()}` : data.full
    const probe = new Image()
    probe.onload = () => {
      // a late answer may not repaint a closed lightbox or another image
      if (!this.lb || this.lb.token !== token) return
      this.lb.loadingUrl = null
      state.hidden = true
      img.style.backgroundImage = `url('${url}')`
      this.lb.paintedUrl = data.full
    }
    probe.onerror = () => {
      if (!this.lb || this.lb.token !== token) return
      this.lb.loadingUrl = null
      this.lb.paintedUrl = null
      state.hidden = false
      state.innerHTML = `<span>This image could not be shown.
        The original is safe on disk, the display size failed to load.<br>
        <button type="button" class="link" id="lbRetry" style="color:#fff;text-decoration:underline">Try again</button></span>`
      state.querySelector("#lbRetry").addEventListener("click", () => this.loadImage(data, true))
    }
    probe.src = url
  }

  nav(direction) {
    const lb = this.lb
    if (!lb) return
    const list = this.shownTiles()
    if (!list.length) return
    const index = list.findIndex(t => t.dataset.id === lb.id)
    const next = list[(Math.max(index, 0) + direction + list.length) % list.length]
    lb.id = next.dataset.id
    lb.formFor = null
    lb.paintedUrl = null
    lb.opening = false
    this.paint()
  }

  deleteCurrent() {
    const lb = this.lb
    if (!lb) return
    const data = this.tileData(lb.id)
    if (!data) return

    this.hook.pushEvent("gallery_delete", {id: lb.id})
    this.showUndoBar(lb.id, data.filename)

    if (data.count <= 1) {
      this.closeLightbox()
    } else {
      this.nav(1)
    }
  }

  // the server re-rendered under an open lightbox: follow the image,
  // or its neighbour when it is gone, and let go only of an empty gallery
  refreshLightbox() {
    const lb = this.lb
    if (!lb) return

    if (this.tileData(lb.id)) {
      this.paint()
      return
    }

    const list = this.shownTiles()
    if (!list.length) return this.closeLightbox()
    const fallback = list[Math.min(lb.lastIndex, list.length - 1)]
    lb.id = fallback.dataset.id
    lb.formFor = null
    lb.paintedUrl = null
    lb.opening = false
    this.paint()
  }

  closeLightbox(silent) {
    if (this.root) {
      // a film goes quiet the moment the lightbox leaves
      const film = this.root.querySelector("video")
      if (film) film.pause()
      const bar = document.getElementById("undoBar")
      if (bar && this.root.contains(bar)) document.body.appendChild(bar)
      if (this.root.open) this.root.close()
      this.root.remove()
      this.root = null
    }
    document.body.style.overflow = ""
    document.body.classList.remove("has-overlay")
    if (this.lb && !silent) {
      const tile = this.server.querySelector(`[data-id="${this.lb.id}"]`)
      const prev = this.lb.prevFocus
      if (tile) tile.focus()
      else if (prev && document.contains(prev)) prev.focus()
    }
    this.lb = null
  }

  savedNote(problem) {
    const el = this.root && this.root.querySelector("#lbSaved")
    if (!el) return
    clearTimeout(this.savedTimer)
    el.textContent = problem || t("Saved · just now")
    this.savedTimer = setTimeout(() => {
      el.textContent = t("The date saves itself and sorts the gallery.")
    }, SAVED_MS)
  }

  keydown(e) {
    if (!this.lb) return

    if (e.key === "Escape") {
      if (e.target.matches && e.target.matches("input, textarea")) {
        e.target.blur()
      } else {
        this.closeLightbox()
      }
      e.preventDefault()
      return
    }

    if (e.key === "Tab") {
      const focusables = [...this.root.querySelectorAll(FOCUSABLE)].filter(el => el.offsetParent !== null)
      if (!focusables.length) return
      const first = focusables[0]
      const last = focusables[focusables.length - 1]
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault()
        last.focus()
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault()
        first.focus()
      }
      return
    }

    if (e.target.matches && e.target.matches("input, textarea")) return

    if (e.key === "ArrowLeft") {
      e.preventDefault()
      this.nav(-1)
    } else if (e.key === "ArrowRight") {
      e.preventDefault()
      this.nav(1)
    }
  }

  /* ================= delete's way back ================= */

  showUndoBar(id, filename) {
    this.removeUndoBar()

    const bar = document.createElement("div")
    bar.id = "undoBar"
    bar.className = "fixed left-4 bottom-4 z-[95] flex items-center gap-3 bg-paper px-4 py-3 text-[13px]"
    bar.style.borderRadius = "var(--tt-radius-pop)"
    bar.style.border = "1px solid var(--tt-rule)"
    bar.style.boxShadow = "0 14px 34px rgb(var(--tt-shadow) / .2)"
    // the file name is the only part that is not a sentence, so it is
    // put into the sentence rather than glued in front of it
    bar.innerHTML = `<span>${t("%{name} deleted", {name: `<b>${esc(filename)}</b>`})}</span>
      <button type="button" class="link" id="undoBtn">${esc(t("Undo"))}</button>
      <span class="note num" id="undoLeft">${UNDO_S} s</span>`

    // a modal dialog makes the page inert; while the lightbox is open
    // the bar lives inside it, so Undo stays clickable
    ;(this.root || document.body).appendChild(bar)

    let left = UNDO_S
    this.undoTimer = setInterval(() => {
      left -= 1
      const label = bar.querySelector("#undoLeft")
      if (label) label.textContent = `${left} s`
      if (left <= 0) this.removeUndoBar()
    }, 1000)

    bar.querySelector("#undoBtn").addEventListener("click", () => {
      this.hook.pushEvent("gallery_undo", {id})
      this.removeUndoBar()
    })
  }

  removeUndoBar() {
    clearInterval(this.undoTimer)
    const bar = document.getElementById("undoBar")
    if (bar) bar.remove()
  }
}
