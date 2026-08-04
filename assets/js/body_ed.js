/* BodyEd · the one door to the body editor. The CodeMirror view mounts
   behind it in the next step; until then the server-rendered textarea
   does the writing, wired to the same events:

   in:  sync_body {text}, set_readonly {readOnly}
   out: body_changed {text} (debounced), editor_activity (throttled) */
export default {
  mounted() {
    const ta = this.el.querySelector("textarea")
    this.ta = ta
    let debounce = null
    let lastPing = 0

    ta.addEventListener("input", () => {
      const now = Date.now()
      if (now - lastPing > 2000) {
        lastPing = now
        this.pushEvent("editor_activity", {})
      }
      clearTimeout(debounce)
      debounce = setTimeout(() => {
        this.pushEvent("body_changed", {text: ta.value})
      }, 300)
    })

    this.handleEvent("sync_body", ({text}) => {
      if (ta.value !== text) ta.value = text
    })
    this.handleEvent("set_readonly", ({readOnly}) => {
      ta.readOnly = readOnly
      if (readOnly && document.activeElement === ta) ta.blur()
    })

    ta.addEventListener("mousedown", event => {
      if (ta.readOnly) {
        event.preventDefault()
        this.pushEvent("ask_takeover", {})
      }
    })
  },
}
