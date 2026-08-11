/* Fixed-position placement, next to an anchor: no scroll container, no
   overflow and no backdrop-filter stacking context can ever clip an
   element placed this way. On a short window it takes the taller side
   and scrolls inside it.

   The wordmark menu and the bar popovers both stand on this. */

export function placeFixed(el, anchor, align, viewport) {
  const vp = viewport || {width: window.innerWidth, height: window.innerHeight}
  const r = anchor.getBoundingClientRect()
  el.style.maxHeight = ""
  const gap = 6, edge = 8
  const below = vp.height - r.bottom - gap - edge
  const above = r.top - gap - edge
  const want = el.offsetHeight
  if (want > below && above > below) {
    const h = Math.max(120, Math.min(want, Math.round(above)))
    el.style.maxHeight = h + "px"
    el.style.top = Math.round(r.top - gap - h) + "px"
  } else {
    if (want > below) el.style.maxHeight = Math.max(120, Math.round(below)) + "px"
    el.style.top = Math.round(r.bottom + gap) + "px"
  }
  if (align === "right") {
    el.style.left = "auto"
    el.style.right = Math.max(8, Math.round(vp.width - r.right)) + "px"
  } else {
    const w = el.offsetWidth
    el.style.right = "auto"
    el.style.left = Math.round(Math.max(8, Math.min(r.left, vp.width - w - 8))) + "px"
  }
}

/* A popover in the bar: placed the moment it appears, and again on
   every resize and repaint. */
export const PlacePop = {
  mounted() {
    this.place()
    this.onResize = () => this.place()
    window.addEventListener("resize", this.onResize)
  },
  updated() { this.place() },
  destroyed() { window.removeEventListener("resize", this.onResize) },
  place() {
    const anchor = document.querySelector(this.el.dataset.anchor)
    if (anchor) placeFixed(this.el, anchor, this.el.dataset.align || "right")
  },
}
