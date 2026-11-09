// The export of an entry: a click on a mark that carries `data-export`.
//
// A plain download link is a navigation of the page, and a second click
// on another link cancels the first while it still waits for its
// answer. So every export runs in a hidden frame of its own: two clicks
// are two downloads, side by side, and the page stays where it is.
//
// The mark answers the click at once, so nobody clicks twice because
// nothing seemed to happen. It turns into a tick (`sent`) and goes back
// after a moment; the browser shows the download itself from there. An
// answer that is a page and not a file is an error, and the mark says
// so (`failed`). The motion is one transition in the CSS, never a loop.
//
// A click with a modifier key, or one without this script, is still the
// plain link.
import {t} from "./i18n"

const SHOWN_MS = 2500
// A frame is kept long enough for its download to be handed over.
const FRAME_MS = 60_000

export function initExportGet(doc = document) {
  doc.addEventListener("click", event => {
    const mark = event.target.closest?.("a[data-export]")
    if (!mark || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    event.preventDefault()
    // one export per mark at a time: a second click while it shows
    // `sent` is the impatient click this is here to spare
    if (mark.classList.contains("sent")) return

    start(doc, mark)
  })
}

function start(doc, mark) {
  const frame = doc.createElement("iframe")
  frame.hidden = true
  frame.src = mark.href

  // A download never loads a document into the frame. Whatever does
  // load (a 404, the sign-in page, a 413) is the export failing.
  frame.addEventListener("load", () => {
    const text = frame.contentDocument?.body?.textContent?.trim()
    if (text) show(mark, "failed", t("The export failed. Try again."))
  })

  doc.body.appendChild(frame)
  setTimeout(() => frame.remove(), FRAME_MS)

  show(mark, "sent", t("Download started"))
}

function show(mark, state, words) {
  // the row in the editor menu says it in words, the round mark on a
  // card in its title
  const label = mark.querySelector("[data-export-label]")
  const say = words => { if (label) label.textContent = words; else mark.title = words }
  mark._exportWords ??= label ? label.textContent : mark.title

  clearTimeout(mark._exportTimer)
  mark.classList.remove("sent", "failed")
  mark.classList.add(state)
  say(words)

  mark._exportTimer = setTimeout(() => {
    mark.classList.remove(state)
    say(mark._exportWords)
  }, SHOWN_MS)
}
