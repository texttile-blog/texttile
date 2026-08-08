// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/texttile"
import topbar from "../vendor/topbar"
import BodyEd from "./body_ed"
import Gallery from "./gallery"

/* The Last-saved line of a screen that saves instantly.

   A screen without a Save button owes the eye an answer, and a grey
   line that quietly rewrites itself is not one. So the line is loud
   for a moment and quiet the rest of the time: every save turns it to
   the accent, ticks it, and says "Saved"; a few seconds later it fades
   back to the stamp of the clock time. A note about the change (a
   restored version, an address that is taken) stays in the loud state
   as long as it stands, because that is a sentence to read, not a
   stamp to glance at. */
const FLASH_MS = 2600

const SavedTicker = {
  mounted() {
    // the line arrives with the last save already on it; only a save
    // that happens while somebody is watching is worth a flash
    this.at = Number(this.el.dataset.at || 0)
    this.timer = setInterval(() => this.paint(), 1000)
    this.paint()
  },
  updated() { this.paint() },
  destroyed() { clearInterval(this.timer); clearTimeout(this.fade) },

  paint() {
    const now = Date.now()
    const at = Number(this.el.dataset.at || now)
    const note = this.el.dataset.note
    const until = Number(this.el.dataset.noteUntil || 0)

    // a note is a sentence to read, so the loud state lasts as long as
    // the sentence stands
    if (at !== this.at) {
      this.at = at
      this.flash(note ? Math.max(FLASH_MS, until - now) : FLASH_MS)
    }

    if (note && now < until) { this.el.textContent = note; return }

    const d = new Date(at)
    const pad = n => String(n).padStart(2, "0")
    const fresh = (now - at) / 1000 < 20
    const wide = window.matchMedia("(min-width: 768px)").matches

    if (this.el.classList.contains("fresh")) { this.el.textContent = "Saved"; return }
    // a phone bar has room for the stamp, not for the sentence
    if (!wide) {
      this.el.textContent = fresh ? "saved" : `saved ${pad(d.getHours())}:${pad(d.getMinutes())}`
      return
    }
    this.el.textContent = fresh
      ? "Last saved · just now"
      : `Last saved ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
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

/* A popover in the bar: positioned fixed and placed next to its anchor
   the moment it appears, so no scroll container, no overflow and no
   backdrop-filter stacking context can ever clip it. */
const PlacePop = {
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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, SavedTicker, PlacePop, BodyEd, Gallery},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

/* ==================================================================
   THE WORDMARK MENU · positioned fixed and placed here, so no scroll
   container, no overflow and no stacking context can ever clip it. On
   a short window it takes the taller side and scrolls inside it.
   ================================================================== */
function placeFixed(el, anchor, align) {
  const r = anchor.getBoundingClientRect()
  el.style.maxHeight = ""
  const gap = 6, edge = 8
  const below = window.innerHeight - r.bottom - gap - edge
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
    el.style.right = Math.max(8, Math.round(window.innerWidth - r.right)) + "px"
  } else {
    const w = el.offsetWidth
    el.style.right = "auto"
    el.style.left = Math.round(Math.max(8, Math.min(r.left, window.innerWidth - w - 8))) + "px"
  }
}

const menuEl = () => document.getElementById("navMenu")
const wmBtn = () => document.getElementById("wmBtn")

function toggleMenu() {
  const menu = menuEl()
  if (!menu) return
  if (menu.hidden) {
    menu.hidden = false
    wmBtn().setAttribute("aria-expanded", "true")
    placeFixed(menu, wmBtn(), "left")
  } else {
    closeMenu()
  }
}

function closeMenu() {
  const menu = menuEl()
  if (!menu || menu.hidden) return
  menu.hidden = true
  const btn = wmBtn()
  if (btn) btn.setAttribute("aria-expanded", "false")
}

document.addEventListener("click", event => {
  /* a control that rewrote its own row is out of the document by the
     time the click arrives here. A detached target must not read as
     "somewhere outside the menu". */
  if (!event.target.isConnected) return

  if (event.target.closest("#wmBtn")) {
    toggleMenu()
    return
  }

  const toggle = event.target.closest("[data-toggle-password]")
  if (toggle) {
    const input = document.getElementById(toggle.dataset.togglePassword)
    if (input) {
      const show = input.type === "password"
      input.type = show ? "text" : "password"
      toggle.textContent = show ? "Hide" : "Show"
      input.focus()
    }
    return
  }

  if (!event.target.closest("#navMenu")) closeMenu()
})

/* THE KEY DIGITS · a digit jumps to its section from anywhere on the
   desk. The keys sleep while you are typing in a field, and each digit
   only works once its section exists: a section row in the wordmark
   menu carries its digit as data-key. */
function typingIn(el) {
  return el && (el.isContentEditable ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName))
}

document.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    closeMenu()
    return
  }
  if (event.metaKey || event.ctrlKey || event.altKey) return
  if (typingIn(event.target)) return
  if (event.key === "/") {
    const search = document.querySelector("#grid-search input")
    if (search) {
      event.preventDefault()
      search.focus()
    }
    return
  }
  if (!/^[0-9]$/.test(event.key)) return
  const row = document.querySelector(`#navMenu [data-key="${event.key}"]`)
  if (row) {
    closeMenu()
    row.click()
  }
})

window.addEventListener("resize", () => {
  const menu = menuEl()
  if (menu && !menu.hidden) placeFixed(menu, wmBtn(), "left")
})


// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

