/* Gallery, the door: the tiles block's client half (upload queue,
   drag-to-sort, lightbox, undo) loads as its own chunk the moment an
   editor is on screen - never on the grid or the settings. The
   contract with the server lives in gallery_core. */
export default {
  async mounted() {
    this._loading = import("./gallery_core")
    const core = await this._loading
    if (this._dead) return
    core.mount(this)
  },
  updated() {
    if (this.updated_core) this.updated_core()
  },
  destroyed() {
    this._dead = true
    if (this.destroyed_core) this.destroyed_core()
  },
}
