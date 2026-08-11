/* THE TRANSPORT

   Long polling is the way in for a reader behind a proxy that refuses
   a WebSocket. It is a poor way in for anybody else: the browser gives
   one site about six connections, every open tab holds one of them
   open for its poll, and from the seventh tab on the pages wait for
   each other. A waiting page is worse than a broken one, because it
   looks exactly like a working one - the fields take letters, the
   buttons take clicks, and nothing arrives.

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

export function watchLiveness() {
  let lateTimer = null

  function watchTheLine() {
    const main = document.querySelector("[data-phx-main]")
    const live = !main || main.classList.contains("phx-connected")

    if (live) {
      clearTimeout(lateTimer)
      lateTimer = null
      document.documentElement.classList.remove("phx-late")
    } else if (lateTimer === null) {
      lateTimer = setTimeout(() => document.documentElement.classList.add("phx-late"), LATE_MS)
    }
  }

  setInterval(watchTheLine, 1000)
  addEventListener("visibilitychange", watchTheLine)
  watchTheLine()
}
