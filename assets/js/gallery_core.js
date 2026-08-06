/* The tiles block's client half, ported from round-14 with the touch
   mechanics the imaedge proof settled on.

   in:  the server tiles in #tileServer (truth, re-rendered on every
        gallery_changed), gallery_moved {id, note} when somebody else
        sorted
   out: gallery_reorder {id, ids}, gallery_set_date {id, date},
        gallery_set_meta {id, alt, caption}, gallery_delete {id},
        gallery_undo {id}, gallery_refresh - and files as one POST per
        file to the upload url

   The hook owns three things LiveView must not touch: the local
   upload tiles in #tileLocal (phx-update="ignore"), the lightbox it
   appends to <body>, and the undo bar. While a tile is held,
   #tileServer carries data-dragging and app.js skips its patches; the
   drop ends with gallery_refresh, whose rev bump re-renders every
   tile and reconciles whatever was skipped. */

const MAX_PARALLEL = 2
const TOUCH_DRAG_DELAY_MS = 200
const DRAG_THRESHOLD_PX = 9
const TAP_MS = 500
const SWIPE_THRESHOLD_PX = 48
const SCROLL_EDGE_PX = 64
const SCROLL_STEP_PX = 14
const NOTE_MS = 2600
const JMOVE_MS = 2600
const UNDO_S = 10
const META_DEBOUNCE_MS = 500
const SAVED_MS = 4000

const FOCUSABLE = "a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex='-1'])"

function esc(text) {
  return String(text).replace(/[&<>"']/g, c =>
    ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"})[c])
}

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
    this.noteTimer = setTimeout(() => {
      this.note.textContent = "Grab an image to sort it. Tap one to see it big."
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
    const images = [...fileList].filter(f => /^image\//.test(f.type))
    for (const file of images) {
      this.records.push({
        id: "u" + ++this.uid,
        file,
        name: file.name,
        objurl: URL.createObjectURL(file),
        status: "queued",
        pct: 0,
      })
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
        record.error = (xhr.response && xhr.response.error) || "upload failed"
        this.noteTile(`${record.name} failed to upload. Retry or remove it.`)
      }
      this.scheduleRender()
      this.pump()
    }
    xhr.onerror = xhr.ontimeout = () => {
      this.active -= 1
      record.xhr = null
      record.status = "failed"
      record.error = "upload failed"
      this.noteTile(`${record.name} failed to upload. Retry or remove it.`)
      this.scheduleRender()
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
    this.onWay.textContent = away ? ` · ${away} on the way` : ""
  }

  localTile(r) {
    const st =
      r.status === "queued" ? "queued"
      : r.status === "uploading" ? `uploading ${r.pct}%`
      : r.status === "processing"
        ? `<i class="spin inline-block w-[8px] h-[8px] rounded-full border border-white border-t-transparent"></i>processing`
        : esc(r.error || "upload failed")

    const bar =
      r.status === "failed"
        ? ""
        : `<span class="tile-bar"><i style="width:${r.status === "queued" ? 0 : r.status === "processing" ? 100 : r.pct}%"></i></span>`

    const buttons =
      r.status === "failed"
        ? `<button type="button" class="tile-x" data-act="retry">Retry</button>
           <button type="button" class="tile-x" data-act="remove">Remove</button>`
        : `<button type="button" class="tile-x" data-act="cancel">Cancel</button>`

    return `<div class="tile up ${r.status}" data-local-id="${r.id}"
      style="background-image:url('${r.objurl}')" aria-label="${esc(r.name)}, ${esc(r.status)}">
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
    if (!d || d.held || d.mode === "scroll") return
    d.held = true
    d.initialOrder = this.currentIds()
    d.tile.classList.add("lift", "slot")
    this.server.setAttribute("data-dragging", "1")
    if (navigator.vibrate) navigator.vibrate(8)
  }

  pointerMove(e) {
    const d = this.drag
    if (!d || e.pointerId !== d.pointerId) return

    const dx = e.clientX - d.startX
    const dy = e.clientY - d.startY
    const distance = Math.hypot(dx, dy)

    if (!d.held && !d.mode && distance > DRAG_THRESHOLD_PX) {
      clearTimeout(d.timer)
      if (e.pointerType === "mouse" || Math.abs(dx) >= Math.abs(dy)) {
        this.lift()
      } else {
        // the finger wants the page; tiles have touch-action none, so
        // the scroll is driven by hand (the imaedge mechanic)
        d.mode = "scroll"
      }
    }

    if (d.mode === "scroll") {
      this.scroller().scrollBy(0, d.lastY - e.clientY)
      d.moved = true
    } else if (d.held) {
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
    this.drag = null

    if (d.held) {
      d.tile.classList.remove("lift", "slot")
      this.server.removeAttribute("data-dragging")

      const ids = this.currentIds()
      if (d.moved && ids.join("\n") !== d.initialOrder.join("\n")) {
        this.hook.pushEvent("gallery_reorder", {id: d.id, ids})
      }
      // reconcile whatever patch the drag held off (and a cancelled
      // drag's optimistic order); the rev bump re-renders every tile
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

  tileData(id) {
    const list = this.tiles()
    const index = list.findIndex(t => t.dataset.id === id)
    if (index < 0) return null
    const t = list[index]
    return {
      id,
      index,
      count: list.length,
      filename: t.dataset.filename,
      date: t.dataset.date,
      alt: t.dataset.alt,
      caption: t.dataset.caption,
      full: t.dataset.full,
      original: t.dataset.original,
    }
  }

  openLightbox(id) {
    const data = this.tileData(id)
    if (!data || this.lb) return

    this.lb = {
      id,
      lastIndex: data.index,
      token: 0,
      formFor: null,
      paintedUrl: null,
      prevFocus: document.activeElement,
    }
    this.buildLightbox()
    document.body.style.overflow = "hidden"
    this.paint()
    this.root.focus()
  }

  buildLightbox() {
    const root = document.createElement("div")
    root.id = "lbRoot"
    root.className = "fixed inset-0 z-[90] flex flex-col"
    root.style.background = "var(--tt-lightbox)"
    root.setAttribute("role", "dialog")
    root.setAttribute("aria-modal", "true")
    root.setAttribute("aria-label", "Image, full size")
    root.tabIndex = -1

    root.innerHTML = `
      <div class="flex items-center gap-3 px-4 h-[52px] flex-none text-white/80 text-[12.5px]">
        <span id="lbCount" class="num"></span>
        <span class="sp"></span>
        <a id="lbOrig" class="text-white/85 hover:text-white text-[13px] px-3 py-1.5 rounded underline underline-offset-2"
           target="_blank" rel="noopener">Open original</a>
        <button type="button" id="lbClose" class="text-white/85 hover:text-white text-[13px] px-3 py-1.5 rounded"
           style="box-shadow: inset 0 0 0 1px rgba(255,255,255,.35)" aria-label="Close">Close</button>
      </div>
      <div id="lbStage" class="relative flex-1 min-h-0 flex items-center justify-center px-2 gap-2" style="touch-action:pan-y">
        <button type="button" class="lb-nav text-white/70 hover:text-white text-[30px] leading-none px-3 py-6 flex-none"
           data-nav="-1" aria-label="Previous image">&#8249;</button>
        <div class="relative flex-1 h-full min-w-0 flex items-center justify-center">
          <div id="lbImg" class="w-full h-full bg-center bg-contain bg-no-repeat" role="img" aria-label=""></div>
          <div id="lbState" class="absolute inset-0 grid place-items-center text-white/80 text-[13px] text-center px-6" hidden></div>
        </div>
        <button type="button" class="lb-nav text-white/70 hover:text-white text-[30px] leading-none px-3 py-6 flex-none"
           data-nav="1" aria-label="Next image">&#8250;</button>
      </div>
      <div id="lbFoot" class="flex-none bg-paper border-t border-rule px-4 py-3">
        <div class="max-w-[900px] mx-auto">
          <p class="text-[13px]"><b id="lbName"></b> <span class="note" id="lbMeta"></span></p>
          <div class="grid gap-3 md:grid-cols-[1fr_1fr_190px] items-end mt-2">
            <span>
              <label class="lab block mb-[3px]" for="lbAlt">Alt text</label>
              <input type="text" id="lbAlt" placeholder="What the picture shows">
            </span>
            <span>
              <label class="lab block mb-[3px]" for="lbCap">Caption</label>
              <input type="text" id="lbCap" placeholder="Shown under the picture">
            </span>
            <span>
              <label class="lab block mb-[3px]" for="lbDate">Date</label>
              <input type="datetime-local" id="lbDate" step="60">
            </span>
          </div>
          <div class="flex items-center gap-3 mt-3">
            <span class="note" id="lbSaved">Every change here saves itself.</span>
            <span class="sp"></span>
            <button type="button" class="btn sm" id="lbDelete">Delete image</button>
          </div>
        </div>
      </div>`

    document.body.appendChild(root)
    this.root = root

    root.querySelector("#lbClose").addEventListener("click", () => this.closeLightbox())
    root.querySelectorAll("[data-nav]").forEach(b =>
      b.addEventListener("click", () => this.nav(parseInt(b.dataset.nav, 10)))
    )
    root.querySelector("#lbDelete").addEventListener("click", () => this.deleteCurrent())

    const alt = root.querySelector("#lbAlt")
    const cap = root.querySelector("#lbCap")
    const metaChanged = () => {
      const id = this.lb && this.lb.id
      if (!id) return
      clearTimeout(this.metaTimer)
      this.metaTimer = setTimeout(() => {
        this.hook.pushEvent(
          "gallery_set_meta",
          {id, alt: alt.value, caption: cap.value},
          reply => this.savedNote(reply.ok ? null : "That picture was deleted a moment ago")
        )
      }, META_DEBOUNCE_MS)
    }
    alt.addEventListener("input", metaChanged)
    cap.addEventListener("input", metaChanged)

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
          this.savedNote("That date could not be read")
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

    const caption = data.caption ? ` · “${data.caption}”` : ""
    this.root.querySelector("#lbMeta").textContent =
      ` · ${data.date.slice(0, 10)} · image ${data.index + 1} of ${data.count}${caption}`

    // never write over what somebody is typing right now
    if (lb.formFor !== lb.id) {
      this.root.querySelector("#lbAlt").value = data.alt
      this.root.querySelector("#lbCap").value = data.caption
      this.root.querySelector("#lbDate").value = data.date
      lb.formFor = lb.id
    }

    if (lb.paintedUrl !== data.full) this.loadImage(data)
  }

  loadImage(data, bust) {
    const lb = this.lb
    const token = ++lb.token
    const img = this.root.querySelector("#lbImg")
    const state = this.root.querySelector("#lbState")

    img.style.backgroundImage = ""
    img.setAttribute("aria-label", data.alt || data.filename)
    state.hidden = false
    state.textContent = "Loading the full size…"

    const url = bust ? `${data.full}${data.full.includes("?") ? "&" : "?"}r=${Date.now()}` : data.full
    const probe = new Image()
    probe.onload = () => {
      // a late answer may not repaint a closed lightbox or another image
      if (!this.lb || this.lb.token !== token) return
      state.hidden = true
      img.style.backgroundImage = `url('${url}')`
      this.lb.paintedUrl = data.full
    }
    probe.onerror = () => {
      if (!this.lb || this.lb.token !== token) return
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
    const list = this.tiles()
    if (!list.length) return
    const index = list.findIndex(t => t.dataset.id === lb.id)
    const next = list[(Math.max(index, 0) + direction + list.length) % list.length]
    lb.id = next.dataset.id
    lb.formFor = null
    lb.paintedUrl = null
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

    const list = this.tiles()
    if (!list.length) return this.closeLightbox()
    const fallback = list[Math.min(lb.lastIndex, list.length - 1)]
    lb.id = fallback.dataset.id
    lb.formFor = null
    lb.paintedUrl = null
    this.paint()
  }

  closeLightbox(silent) {
    if (this.root) {
      this.root.remove()
      this.root = null
    }
    document.body.style.overflow = ""
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
    el.textContent = problem || "Saved · just now"
    this.savedTimer = setTimeout(() => {
      el.textContent = "Every change here saves itself."
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
    bar.innerHTML = `<span><b>${esc(filename)}</b> deleted</span>
      <button type="button" class="link" id="undoBtn">Undo</button>
      <span class="note num" id="undoLeft">${UNDO_S} s</span>`
    document.body.appendChild(bar)

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
