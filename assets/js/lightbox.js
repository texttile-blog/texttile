/* THE ONE LIGHTBOX
 *
 * Three surfaces show a picture full size: the body editor's
 * thumbnails, the gallery block, and the reader's page. They wear the
 * same classes and promise the same behaviour - a count, a way out, an
 * arrow on each side, the arrow keys, a 48px swipe, wrap-around, a
 * film that only plays when it was the thing tapped - and this module
 * is that behaviour, once.
 *
 * The paging arithmetic and the swipe rule are pure and node-tested.
 * `openLightbox` is the standard dialog (the body editor uses it
 * whole); the gallery and the reader page keep shells of their own -
 * one is rewritten under a live LiveView, the other is server-rendered
 * so the page works without a script - and drive them with the same
 * helpers.
 */

import {t, esc} from "./i18n.js"

export const SWIPE_PX = 48

export const FOCUSABLE =
  "button, [href], input, select, textarea, video, [tabindex]:not([tabindex='-1'])"

/* one step through a row that wraps in both directions */
export function wrapIndex(at, step, count) {
  return (at + step + count) % count
}

/* What a pointer gesture means: a page step, or nothing. Mostly
   horizontal and longer than the threshold; left drags page forward. */
export function swipeStep(dx, dy, threshold = SWIPE_PX) {
  if (Math.abs(dx) <= threshold || Math.abs(dx) <= Math.abs(dy)) return 0
  return dx < 0 ? 1 : -1
}

/* swipe on a stage: pointer events, so one path covers touch and pen
   and the mouse keeps the arrows to itself */
export function attachSwipe(stage, nav) {
  let sx = null, sy = null
  stage.addEventListener("pointerdown", e => {
    if (e.pointerType === "mouse") return
    sx = e.clientX
    sy = e.clientY
  })
  stage.addEventListener("pointerup", e => {
    if (sx === null) return
    const step = swipeStep(e.clientX - sx, e.clientY - sy)
    sx = null
    if (step) nav(step)
  })
  stage.addEventListener("pointercancel", () => { sx = null })
}

/* Tab stays inside the overlay: the page behind it is not there. */
export function trapTab(root) {
  root.addEventListener("keydown", e => {
    if (e.key !== "Tab") return
    const focusables = [...root.querySelectorAll(FOCUSABLE)].filter(el => el.offsetParent !== null)
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
  })
}

/* What stands on the stage for one item. A film only plays when it was
   the thing tapped: paging past one must neither start nor fetch it.
   item: {film, poster, src, caption} - `film` set makes it a film with
   `poster` behind it; otherwise `src` is the picture. */
export function mediaNode(item, playing) {
  if (item.film) {
    const film = document.createElement("video")
    film.controls = true
    film.playsInline = true
    film.preload = playing ? "metadata" : "none"
    if (item.poster) film.poster = item.poster
    film.src = item.film
    film.setAttribute("aria-label", item.caption || "")
    if (playing) film.play().catch(() => {})
    return film
  }
  const img = document.createElement("img")
  img.src = item.src
  img.alt = item.caption || ""
  return img
}

/* a film that goes on playing behind a closed lightbox would be heard
   and never seen */
export function quiet(container) {
  const film = container.querySelector("video")
  if (film) film.pause()
}

/* ---- the standard dialog ------------------------------------------
   A native dialog in the top layer, so neither the topbar's
   backdrop-filter nor any z-index can paint over it. The body editor
   uses it whole; an item here is {full, film, alt, original}, with
   `film` null on a video meaning ffmpeg is not through with it yet. */

export function openLightbox(items, at) {
  if (!items.length) return null
  return new DialogLightbox(items, at)
}

class DialogLightbox {
  constructor(items, at) {
    this.items = items
    this.at = Math.max(0, Math.min(at, items.length - 1))
    this.build()
    /* only the thumbnail that was clicked starts playing by itself */
    this.paint(true)
  }

  build() {
    const root = document.createElement("dialog")
    root.className = "lb-root"
    root.id = "mediaLb"
    root.setAttribute("aria-label", t("Full size"))
    root.tabIndex = -1

    const many = this.items.length > 1
    root.innerHTML = `
      <div class="lb-bar-a">
        <span id="mlCount" class="num"></span>
        <span class="sp"></span>
        <a id="mlOrig" class="lb-abtn plain" target="_blank" rel="noopener"
           ><span class="lb-word">${esc(t("Open original"))}</span><span class="lb-word-s">${esc(t("Original"))}</span></a>
        <button type="button" id="mlClose" class="lb-abtn">${esc(t("Close"))}</button>
      </div>
      <div class="lb-stage" id="mlStage">
        <button type="button" class="lb-arrow lb-nav" data-nav="-1"
          aria-label="${esc(t("Previous"))}" ${many ? "" : "hidden"}>&#8249;</button>
        <div class="lb-img" id="mlArt"></div>
        <button type="button" class="lb-arrow lb-nav" data-nav="1"
          aria-label="${esc(t("Next"))}" ${many ? "" : "hidden"}>&#8250;</button>
      </div>
      <p class="lb-cap" id="mlCap"></p>`

    document.body.appendChild(root)
    this.root = root
    this.art = root.querySelector("#mlArt")
    root.showModal()
    document.body.classList.add("has-overlay")
    root.focus()

    /* Escape reaches the dialog as a cancel, so closing stays one path */
    root.addEventListener("cancel", e => { e.preventDefault(); this.close() })
    root.querySelector("#mlClose").addEventListener("click", () => this.close())
    root.querySelectorAll("[data-nav]").forEach(b =>
      b.addEventListener("click", () => this.nav(parseInt(b.dataset.nav, 10)))
    )
    /* the ground around the picture is a way out, the picture is not */
    root.addEventListener("click", e => {
      if (e.target === root || e.target.id === "mlStage") this.close()
    })

    this.onKey = e => {
      if (e.key === "ArrowLeft") { e.preventDefault(); this.nav(-1) }
      else if (e.key === "ArrowRight") { e.preventDefault(); this.nav(1) }
    }
    root.addEventListener("keydown", this.onKey)
    trapTab(root)
    attachSwipe(root.querySelector("#mlStage"), step => this.nav(step))
  }

  nav(step) {
    this.at = wrapIndex(this.at, step, this.items.length)
    this.paint(false)
  }

  paint(playing) {
    const item = this.items[this.at]
    const caption = item.alt || item.original || ""

    if (item.video && !item.film) {
      /* ffmpeg is not through with it: the text says so, and nothing
         is fetched that does not exist yet */
      const said = document.createElement("p")
      said.className = "lb-cap"
      said.textContent = t("This film is still being converted. It plays here once that is done.")
      this.art.replaceChildren(said)
    } else if (item.video) {
      this.art.replaceChildren(
        mediaNode({film: item.film, poster: item.full, caption}, playing)
      )
    } else {
      this.art.replaceChildren(mediaNode({src: item.full, caption}, false))
    }

    this.root.querySelector("#mlCount").textContent =
      this.items.length > 1 ? `${this.at + 1} / ${this.items.length}` : ""
    this.root.querySelector("#mlCap").textContent = caption
    const original = this.root.querySelector("#mlOrig")
    original.href = item.original || item.full || "#"
    original.hidden = !item.original
  }

  /* closing twice is no error: the editor closes whatever it holds
     when it goes, and the way out may have run already */
  close() {
    if (!this.root) return
    quiet(this.art)
    this.root.close()
    this.root.remove()
    this.root = null
    document.body.classList.remove("has-overlay")
  }
}
