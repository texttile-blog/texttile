/* Gallery, the door: the tiles block's client half (upload queue,
   drag-to-sort, lightbox, undo) loads as its own chunk the moment an
   editor is on screen - never on the grid or the settings. The
   contract with the server lives in gallery_core.

   The block wears data-ready once that half is alive. A file dropped
   before it is lost without a word, because nothing listens yet: the
   browser tests wait for the flag, and a patch that drops it puts it
   back. */
export default {
  async mounted() {
    this._loading = import("./gallery_core")
    const core = await this._loading
    if (this._dead) return
    core.mount(this)
    this.el.dataset.ready = "1"
  },
  updated() {
    if (!this.updated_core) return
    this.updated_core()
    this.el.dataset.ready = "1"
  },
  destroyed() {
    this._dead = true
    if (this.destroyed_core) this.destroyed_core()
  },
}
