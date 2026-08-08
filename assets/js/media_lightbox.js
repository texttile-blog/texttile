/* THE LIGHTBOX OF THE WORDS
 *
 * The writing surface draws every picture and every film in the text
 * as a thumbnail the size of a stamp. This opens one of them full
 * size, pages through the others in the order the text carries them,
 * and plays a film where it stands.
 *
 * It is the round-14 overlay the gallery uses: a native dialog in the
 * top layer, so neither the topbar's backdrop-filter nor any z-index
 * can paint over it. The bar, the arrows and the caption wear the
 * classes the two other lightboxes wear, so the three look alike.
 *
 * An item is {full, film, alt, original}. `film` set makes it a film,
 * with `full` as its poster; `film` null on a film means ffmpeg is
 * not through with it yet and says so instead.
 */
import {t, esc} from "./i18n"

export function openMedia(items, at) {
  if (!items.length) return null
  return new MediaLightbox(items, at)
}

class MediaLightbox {
  constructor(items, at) {
    this.items = items
    this.at = Math.max(0, Math.min(at, items.length - 1))
    this.build()
    /* only the thumbnail that was clicked starts playing by itself;
       paging past a film must neither start it nor fetch it */
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

    /* swipe: pointer events, so one path covers touch and pen and the
       mouse keeps the arrows to itself */
    const stage = root.querySelector("#mlStage")
    let sx = null, sy = null
    stage.addEventListener("pointerdown", e => {
      if (e.pointerType === "mouse") return
      sx = e.clientX
      sy = e.clientY
    })
    stage.addEventListener("pointerup", e => {
      if (sx === null) return
      const dx = e.clientX - sx, dy = e.clientY - sy
      sx = null
      if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) this.nav(dx < 0 ? 1 : -1)
    })
    stage.addEventListener("pointercancel", () => { sx = null })
  }

  nav(step) {
    const count = this.items.length
    this.at = (this.at + step + count) % count
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
      const film = document.createElement("video")
      film.controls = true
      film.playsInline = true
      film.preload = playing ? "metadata" : "none"
      if (item.full) film.poster = item.full
      film.src = item.film
      film.setAttribute("aria-label", caption)
      this.art.replaceChildren(film)
      if (playing) film.play().catch(() => {})
    } else {
      const img = document.createElement("img")
      img.src = item.full
      img.alt = caption
      this.art.replaceChildren(img)
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
    /* a film that goes on playing behind a closed lightbox would be
       heard and never seen */
    const film = this.art.querySelector("video")
    if (film) film.pause()
    this.root.close()
    this.root.remove()
    this.root = null
    document.body.classList.remove("has-overlay")
  }
}
