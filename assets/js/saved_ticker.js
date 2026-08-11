/* The Last-saved line of a screen that saves instantly.

   A screen without a Save button owes the eye an answer, and a grey
   line that quietly rewrites itself is not one. So the line is loud
   for a moment and quiet the rest of the time: every save turns it to
   the accent, ticks it, and says "Saved"; a few seconds later it fades
   back to the stamp of the clock time. A note about the change (a
   restored version, an address that is taken) stays in the loud state
   as long as it stands, because that is a sentence to read, not a
   stamp to glance at. */

import {t} from "./i18n.js"

const FLASH_MS = 2600

/* What the line says at one moment, as a value: the sentence, and the
   tooltip when one is owed. Pure, so the whole wording matrix - note,
   flash, fresh, narrow bar - is a table test away from a browser. */
export function savedLine({at, now, note, noteUntil, flash, wide}, say = t) {
  // a note is a sentence to read, so it takes the whole line while it
  // stands, and the tooltip is left as it was
  if (note && now < noteUntil) return {text: note}

  const d = new Date(at)
  const pad = n => String(n).padStart(2, "0")
  const clock = `${pad(d.getHours())}:${pad(d.getMinutes())}`

  /* The seconds are not in the words. They changed once a second in
     the corner of the eye while somebody was writing, and they said
     nothing that could be acted on. The exact second is in the
     tooltip, for the one time a year it settles an argument. */
  const title = say("The last save was at %{time}.", {time: `${clock}:${pad(d.getSeconds())}`})

  const fresh = (now - at) / 1000 < 20
  if (flash) return {text: say("Saved"), title}

  // a phone bar has room for the stamp, not for the sentence
  if (!wide) {
    return {text: fresh ? say("saved") : say("saved %{time}", {time: clock}), title}
  }

  return {
    text: fresh ? say("Last saved · just now") : say("Last saved %{time}", {time: clock}),
    title,
  }
}

export const SavedTicker = {
  mounted() {
    // the line arrives with the last save already on it; only a save
    // that happens while somebody is watching is worth a flash
    this.at = Number(this.el.dataset.at || 0)
    this.timer = setInterval(() => this.paint(), 1000)
    this.paint()
  },
  updated() { this.paint() },
  destroyed() { clearInterval(this.timer); clearTimeout(this.fade) },

  /* Where the words go. The editor's line is also a link and carries an
     arrow inside the pill, so there the words live in a span of their
     own and the arrow survives every repaint. Everywhere else the pill
     holds nothing but words and is its own target. */
  words() {
    return this.el.querySelector("[data-words]") || this.el
  },

  paint() {
    const now = Date.now()
    const at = Number(this.el.dataset.at || now)
    const note = this.el.dataset.note
    const noteUntil = Number(this.el.dataset.noteUntil || 0)

    // a note is a sentence to read, so the loud state lasts as long as
    // the sentence stands
    if (at !== this.at) {
      this.at = at
      this.flash(note ? Math.max(FLASH_MS, noteUntil - now) : FLASH_MS)
    }

    const line = savedLine({
      at,
      now,
      note,
      noteUntil,
      flash: this.el.classList.contains("fresh"),
      wide: window.matchMedia("(min-width: 768px)").matches,
    })

    if (line.title) this.el.title = line.title
    this.words().textContent = line.text
  },

  // The class carries the whole loud state, and taking it off and
  // putting it back on in one frame is what starts the animation over
  // when two saves follow each other closely.
  flash(ms) {
    this.el.classList.remove("fresh")
    void this.el.offsetWidth
    this.el.classList.add("fresh")
    clearTimeout(this.fade)
    this.fade = setTimeout(() => {
      this.el.classList.remove("fresh")
      this.paint()
    }, ms)
  },
}
