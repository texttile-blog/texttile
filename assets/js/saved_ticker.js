/* The Last-saved stamp of a screen that saves instantly, and the toast
   that answers every save.

   A screen without a Save button owes the eye an answer, and a grey
   line in the bar that quietly rewrites itself is not one. So the two
   halves are apart: the bar keeps the quiet stamp of the clock time
   and nothing on it moves when a save lands, and the save itself
   answers at the bottom right of the page. The toast says "Saved" for
   a moment and goes away. A note about the change (a restored version,
   an address that is taken) stays as long as the note stands, because
   that is a sentence to read, not a stamp to glance at. */

import {t} from "./i18n.js"

const SAVED_MS = 2600

/* What the stamp says at one moment, as a value: the sentence, and
   the tooltip. Pure, so the wording matrix - fresh, narrow bar - is a
   table test away from a browser. */
export function savedLine({at, now, wide}, say = t) {
  const d = new Date(at)
  const pad = n => String(n).padStart(2, "0")
  const clock = `${pad(d.getHours())}:${pad(d.getMinutes())}`

  /* The seconds are not in the words. They changed once a second in
     the corner of the eye while somebody was writing, and they said
     nothing that could be acted on. The exact second is in the
     tooltip, for the one time a year it settles an argument. */
  const title = say("The last save was at %{time}.", {time: `${clock}:${pad(d.getSeconds())}`})

  const fresh = (now - at) / 1000 < 20

  // a phone bar has room for the stamp, not for the sentence
  if (!wide) {
    return {text: fresh ? say("saved") : say("saved %{time}", {time: clock}), title}
  }

  return {
    text: fresh ? say("Last saved · just now") : say("Last saved %{time}", {time: clock}),
    title,
  }
}

/* What the toast says for one save, and for how long: the note while
   it stands, the plain word with its tick otherwise. */
export function toastLine({now, note, noteUntil}, say = t) {
  if (note && now < noteUntil) {
    return {text: note, ms: Math.max(SAVED_MS, noteUntil - now), tick: false}
  }
  return {text: say("Saved"), ms: SAVED_MS, tick: true}
}

export const SavedTicker = {
  mounted() {
    // the stamp arrives with the last save already on it; only a save
    // that happens while somebody is watching is worth a toast
    this.at = Number(this.el.dataset.at || 0)
    this.timer = setInterval(() => this.paint(), 1000)
    this.paint()
  },
  updated() { this.paint() },
  destroyed() {
    clearInterval(this.timer)
    clearTimeout(this.fade)
    document.getElementById("toast")?.remove()
  },

  /* Where the words of the stamp go: a span of its own where the bar
     keeps other marks beside the words, the element itself elsewhere. */
  words() {
    return this.el.querySelector("[data-words]") || this.el
  },

  paint() {
    const now = Date.now()
    const at = Number(this.el.dataset.at || now)

    if (at !== this.at) {
      this.at = at
      this.show(toastLine({
        now,
        note: this.el.dataset.note,
        noteUntil: Number(this.el.dataset.noteUntil || 0),
      }))
    }

    const line = savedLine({at, now, wide: window.matchMedia("(min-width: 768px)").matches})
    this.el.title = line.title
    this.words().textContent = line.text
  },

  /* The toast is one element on the body, made on the first save and
     reused after: the body is outside every LiveView container, so a
     patch of the screen never touches it. The class carries the whole
     shown state, and taking it off and putting it back on in one
     frame is what starts the entrance over when two saves follow each
     other closely. */
  show({text, ms, tick}) {
    const el = toast()
    el.textContent = text
    el.classList.toggle("tick", tick)
    el.classList.remove("on")
    void el.offsetWidth
    el.classList.add("on")
    clearTimeout(this.fade)
    this.fade = setTimeout(() => el.classList.remove("on"), ms)
  },
}

function toast() {
  let el = document.getElementById("toast")
  if (!el) {
    el = document.createElement("div")
    el.id = "toast"
    el.className = "toast"
    el.setAttribute("role", "status")
    document.body.append(el)
  }
  return el
}
