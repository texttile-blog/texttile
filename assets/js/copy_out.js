// Handing one value over: the lines of an entry in the editor, the
// backup token in Settings. Both are read once and pasted somewhere
// else, never edited here.
//
// So the field picks all of itself when it is touched - one click, or
// one key for whoever never reaches for the button - and the button
// says what it did instead of leaving a word beside it.
//
// Both listeners sit on the block itself and are hung once, in
// `mounted`. The block outlives every render, while the field and the
// button inside it are patched: a flag written on them would be wiped
// by the next patch (the server never writes it), and a hook that
// wired them again on every update would end up copying once per
// patch. `focusin` and not `focus`, because only the first travels up
// to the block, and it gives the keyboard the same as the mouse.
import {t} from "./i18n"

export default {
  mounted() {
    this.el.addEventListener("focusin", (event) => {
      if (event.target.matches("textarea")) event.target.select()
    })

    this.el.addEventListener("click", (event) => {
      const button = event.target.closest("[data-copy]")
      if (button && this.el.contains(button)) this.copy(button)
    })
  },

  destroyed() { clearTimeout(this.timer) },

  async copy(button) {
    const field = this.el.querySelector("textarea")
    if (!field) return

    // the button answers for itself, the way Save version does, and it
    // only says it copied when the browser says so
    button.textContent = (await this.hand(field)) ? t("Copied") : t("Now press the copy key")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { button.textContent = t("Copy") }, 2200)
  },

  // The clipboard, by the two ways a browser offers it.
  //
  // `navigator.clipboard` exists on a secure page only. A blog served
  // over plain http, which is every blog reached by the address of a
  // machine in the house, has none at all, so the first way is not a
  // permission that can be refused: the object is not there. The old
  // way is, and it copies what is selected. Whichever ran, the words
  // end up selected, so a keyboard finishes the job either way.
  async hand(field) {
    field.select()

    try {
      await navigator.clipboard.writeText(field.value)
      return true
    } catch (_error) {
      try {
        return document.execCommand("copy")
      } catch (_also) {
        return false
      }
    }
  },
}
