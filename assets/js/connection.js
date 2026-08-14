/* THE TRANSPORT

   Long polling is the way in for a reader behind a proxy that refuses
   a WebSocket. It is the poorer way in for everybody else, and over
   HTTP/1.1 it is a trap: the browser gives one site about six
   connections there, every open tab holds one of them open for its
   poll, and from the seventh tab on the pages wait for each other. A
   waiting page is worse than a broken one, because it looks exactly
   like a working one - the fields take letters, the buttons take
   clicks, and nothing arrives.

   That trap belongs to HTTP/1.1, which is the development server here.
   A site on HTTPS speaks HTTP/2, where every poll of every tab shares
   one connection: ten tabs on long polling were measured against the
   real machine and all ten stayed alive. So the road is worth leaving
   for its latency, not because it strands a site that has a
   certificate.

   Two things sent whole tabs down that road for no reason:

   The threshold. Phoenix drops the WebSocket when the socket does not
   open AND answer a ping inside it. A refused WebSocket does not wait
   for the clock - it errors, and the fallback happens at once - so the
   only thing this number decides is how slow a working WebSocket may
   be before it is thrown away. 2.5 s is not slow. Nine editors
   starting together on one small machine are.

   The memory. Once a tab has fallen back, Phoenix writes that down in
   the session store, and every tab opened out of that one inherits the
   note along with the rest of the session store. One slow moment then
   spread to every tab of the day. So the note goes on the way in: a
   refused WebSocket costs one error per page, which is what it should
   cost. */

export const FALLBACK_MS = 10_000

export function forgetLongpollFallback() {
  try {
    sessionStorage.removeItem("phx:fallback:longpoll")
  } catch (_e) {
    // a browser with no session store has nothing memorised either
  }
}

/* THE PAGE THAT IS NOT LIVE YET

   LiveView says on the screen when a connection it had is gone
   (`phx-client-error`), and the bar swaps its two lines on that. It
   says nothing about a page that has never been live: that page wears
   `phx-loading` and looks finished. Every screen here saves by itself,
   so a page nobody can hear from is a page that quietly throws
   everything away.

   The mark waits a few seconds, because no page is live in its first
   moment and a warning there would be a lie. */
const LATE_MS = 5000

/* THE LINE THAT LOOKS FINE

   The worse case wears no mark at all. A WebSocket that is cut without
   a goodbye - a machine that went to sleep, a network that dropped the
   connection, a proxy that let it go - stays open in the browser.
   Nothing on the screen changes: the transport is still a WebSocket,
   the view still wears phx-connected, and every click goes into a line
   whose other end is gone. The page looks exactly like a working one,
   which is the worst thing a page can look like.

   Only asking finds this. Phoenix asks every 30 seconds, and a browser
   slows a background tab's clock to about once a minute, so its
   question can be minutes away - and until it comes back, whatever is
   typed is thrown away in silence.

   So the page asks for itself while it is in front, and counts how
   long the server has been quiet. Silence is the one symptom that
   every cause shares, so it is the one thing worth watching. A quiet
   line is said in the bar, and it is taken down and built again: the
   words in the editor survive that, because the writing surface is
   `phx-update="ignore"` and keeps what it holds across a rejoin.

   A line that was put down on purpose is left alone. Phoenix marks
   that close as clean, and a page that was disconnected deliberately
   has nothing to repair. */
const ASK_MS = 4000
const QUIET_MS = 8000
const REVIVE_MS = 10_000

/**
 * What the page knows about its line, and what follows from it. On its
 * own, so the rule can be read and tested without a browser around it.
 *
 * `connected` and `clean` come from the socket, `joined` from the view
 * that answers the clicks, `live` from the class LiveView writes on the
 * page, `silent` is how long the server has said nothing.
 *
 * The mark comes at once for a line that has gone quiet, because the
 * silence was already counted. For everything else it waits: no page is
 * live in its first moment, and a warning there would be a lie.
 */
export function readTheLine({transport, connected, clean, joined, live, inFront, silent}) {
  const quiet = connected && !clean && inFront && silent > QUIET_MS
  const standing = connected && live && joined

  return {
    mark: quiet ? "now" : standing ? "never" : "soon",
    revive: quiet,
    note: [
      transport || "no socket",
      joined ? "joined" : "not joined",
      quiet ? `quiet for ${Math.round(silent / 1000)}s` : `answered ${Math.round(silent / 1000)}s ago`,
    ].join(" · "),
  }
}

export function watchLiveness(liveSocket) {
  let lateTimer = null
  let heard = Date.now()
  let asked = 0
  let waiting = false
  let revivedAt = 0
  let written = ""

  const root = document.documentElement
  const socket = () => liveSocket && liveSocket.socket
  const main = () => document.querySelector("[data-phx-main]")
  const view = () => liveSocket && liveSocket.main
  const inFront = () => document.visibilityState === "visible"

  // The channel carries the events; the socket only carries the
  // channel. A joined view is the only one that can answer a click.
  function joined() {
    const held = view()
    return !held || !held.channel || held.channel.state === "joined"
  }

  // One question at a time. An unanswered one keeps its listener on the
  // socket, so asking again over a dead line would pile them up.
  function ask() {
    const line = socket()
    if (!inFront() || waiting || Date.now() - asked < ASK_MS) return
    asked = Date.now()
    waiting = true

    line.ping(() => {
      waiting = false
      heard = Date.now()
    })
  }

  // Down and up again through Phoenix's own machinery, so a build that
  // fails leaves its reconnect running. `disconnect` marks the close as
  // clean, which would stop that, and this close was anything but.
  //
  // The question that was out goes down with the line it was asked on,
  // and the new line starts with a clean slate. Without that it would
  // start owing an answer that can never come, and a page that is
  // waiting for one never asks again.
  function revive() {
    const line = socket()
    if (Date.now() - revivedAt < REVIVE_MS) return
    revivedAt = Date.now()
    forgetTheAsk()

    liveSocket.disconnect(() => {
      line.closeWasClean = false
      liveSocket.connect()
    })
  }

  function forgetTheAsk() {
    heard = Date.now()
    asked = 0
    waiting = false
  }

  function say(mark, note) {
    if (mark === "now") {
      clearTimeout(lateTimer)
      lateTimer = null
      root.classList.add("phx-late")
    } else if (mark === "never") {
      clearTimeout(lateTimer)
      lateTimer = null
      root.classList.remove("phx-late")
    } else if (lateTimer === null) {
      lateTimer = setTimeout(() => root.classList.add("phx-late"), LATE_MS)
    }

    if (note !== written) {
      written = note
      root.setAttribute("data-line", note)
    }
  }

  function watchTheLine() {
    const line = socket()
    const held = main()

    if (!line || !held) {
      say("never", "no page")
      return
    }

    // A line that is down is not a quiet line: LiveView says that one
    // itself and is already building it again.
    if (!line.isConnected() || line.closeWasClean) forgetTheAsk()
    else ask()

    const read = readTheLine({
      // Phoenix's own naming: minification renames the long polling
      // class, and `transport.name` would write that short name down.
      transport: line.transportName(line.transport),
      connected: line.isConnected(),
      clean: line.closeWasClean,
      joined: joined(),
      live: held.classList.contains("phx-connected"),
      inFront: inFront(),
      silent: Date.now() - heard,
    })

    say(read.mark, read.note)
    if (read.revive) revive()
  }

  // Coming back to a tab that was away: its clock was slowed while it
  // sat there, so the silence it brings says nothing about the line.
  // The question goes out now, and the answer decides.
  function backInFront() {
    if (inFront()) forgetTheAsk()
    watchTheLine()
  }

  // Every line that opens is a fresh start, whoever built it: this
  // watch, Phoenix's own reconnect, or a browser coming back to life.
  // A tick can miss the moment the old one went, so this is the one
  // that must not be missed.
  if (socket()) socket().onOpen(forgetTheAsk)

  setInterval(watchTheLine, 1000)
  addEventListener("visibilitychange", backInFront)
  addEventListener("focus", backInFront)
  watchTheLine()
}
