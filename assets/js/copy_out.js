// Handing one value over: the lines of an entry in the editor, the
// backup token in Settings. Both are read once and pasted somewhere
// else, never edited here.
//
// So the field picks all of itself when it is touched - one click, or
// one key for whoever never reaches for the button - and the button
// says what it did instead of leaving a word beside it. `focus` and
// not `click`, so the keyboard gets the same.
import {t} from "./i18n"

export default {
  mounted() { this.wire() },
  updated() { this.wire() },
  destroyed() { clearTimeout(this.timer) },

  wire() {
    const field = this.el.querySelector("textarea")
    const button = this.el.querySelector("[data-copy]")

    if (field && !field.dataset.wired) {
      field.dataset.wired = "1"
      field.addEventListener("focus", () => field.select())
    }
    if (!field || !button || button.dataset.wired) return

    button.dataset.wired = "1"
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(field.value)
      } catch (_error) {
        // No clipboard permission, and no browser offers one on plain
        // http. The words are selected instead, so one key still
        // copies them.
        field.select()
      }
      // the button answers for itself, the way Save version does
      button.textContent = t("Copied")
      clearTimeout(this.timer)
      this.timer = setTimeout(() => { button.textContent = t("Copy") }, 2200)
    })
  },
}
