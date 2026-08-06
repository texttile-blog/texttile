/* BodyEd, the door: the editor itself (CodeMirror and the live
   preview) weighs most of a megabyte, so it loads as its own chunk the
   moment an editor is on screen - never on the grid, the settings or
   the sign-in. The contract with the server lives in body_ed_core. */
export default {
  async mounted() {
    this._loading = import("./body_ed_core")
    const core = await this._loading
    if (this._dead) return
    core.mount(this)
  },
  destroyed() {
    this._dead = true
    if (this.destroyed_core) this.destroyed_core()
  },
}
