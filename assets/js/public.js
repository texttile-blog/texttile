// The public site's whole script: the view counter, the search jump,
// and the lightbox of the reader gallery. Every page works without it;
// the tiles are plain links to the full pictures until this runs.

// The view counter. One line to this server and nowhere else, once per
// page, and the page never waits for the answer. It carries the
// address, the entry it shows and where the reader came from: nothing
// that says who the reader is. No cookie travels with it, because
// nothing here reads one - the server turns the request into a hash it
// cannot undo tomorrow.
//
// The page says whether it counts at all: data-count is missing while
// an admin is signed in, and on every page that is not a reader's.
if (document.body.dataset.count) {
  fetch("/count", {
    method: "POST",
    credentials: "omit",
    keepalive: true,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      p: location.pathname,
      id: document.body.dataset.countEntry || null,
      r: document.referrer || null,
    }),
  }).catch(() => {});
}

// "/" jumps into the search of the text list; Escape empties it.
addEventListener("keydown", (e) => {
  if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
  const el = document.activeElement;
  const typing = el && ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);

  if (e.key === "/" && !typing) {
    const q = document.getElementById("q");
    if (q) {
      e.preventDefault();
      q.focus();
      q.select();
    }
  } else if (e.key === "Escape" && el && el.id === "q" && el.value) {
    el.value = "";
  }
});

// The lightbox: a count, a way out, an arrow on each side, the arrow
// keys, and a 48px swipe. It wraps around in both directions.
//
// Every picture of the page is a link to the original file, so a
// crawler finds the file as it came. The click is taken here instead,
// and the lightbox shows the scaled version from data-full. The
// pictures inside the text come first, the gallery tiles after them,
// in the order the reader meets them.
(function () {
  const lb = document.getElementById("lb");
  if (!lb) return;

  const tiles = [...document.querySelectorAll("#body a.bodypic, #gal a")];
  if (!tiles.length) return;
  let at = -1;

  // `playing` is true only for the tile the reader opened: paging past
  // a film with the arrow keys must not start it, and must not fetch it
  function show(i, playing) {
    at = (i + tiles.length) % tiles.length;
    const tile = tiles[at];
    const inner = tile.querySelector("img");
    const caption = tile.dataset.caption || (inner && inner.alt) || "";
    const art = document.getElementById("lbArt");

    // a gallery tile can be a film: the poster stands behind it until
    // the first frame arrives, and nothing is fetched before that
    if (tile.dataset.video) {
      const film = document.createElement("video");
      film.controls = true;
      film.playsInline = true;
      film.preload = playing ? "metadata" : "none";
      film.poster = tile.dataset.full || "";
      film.src = tile.dataset.video;
      film.setAttribute("aria-label", caption);
      art.replaceChildren(film);
      if (playing) film.play().catch(() => {});
    } else {
      const img = document.createElement("img");
      img.src = tile.dataset.full || tile.href;
      img.alt = caption;
      art.replaceChildren(img);
    }
    document.getElementById("lbCount").textContent = at + 1 + " / " + tiles.length;
    document.getElementById("lbCap").textContent = caption;
  }

  function open(i) {
    show(i, true);
    lb.hidden = false;
    document.documentElement.classList.add("lb-open");
    document.getElementById("lbClose").focus();
  }

  function nav(dir) {
    if (!lb.hidden) show(at + dir, false);
  }

  function close() {
    // a film that goes on playing behind a closed lightbox would be
    // heard and never seen
    const film = document.querySelector("#lbArt video");
    if (film) film.pause();
    lb.hidden = true;
    document.documentElement.classList.remove("lb-open");
    if (at >= 0) tiles[at].focus();
  }

  // A plain click opens the lightbox; a click with a modifier (or the
  // middle button) stays the link it looks like and fetches the
  // original in its own tab.
  tiles.forEach((tile, i) =>
    tile.addEventListener("click", (e) => {
      if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      e.preventDefault();
      open(i);
    })
  );
  document.getElementById("lbClose").addEventListener("click", close);
  document.getElementById("lbPrev").addEventListener("click", () => nav(-1));
  document.getElementById("lbNext").addEventListener("click", () => nav(1));
  lb.addEventListener("click", (e) => {
    if (e.target === lb || e.target.id === "lbStage") close();
  });

  addEventListener("keydown", (e) => {
    if (lb.hidden) return;
    if (e.key === "Escape") close();
    else if (e.key === "ArrowLeft") { e.preventDefault(); nav(-1); }
    else if (e.key === "ArrowRight") { e.preventDefault(); nav(1); }
  });

  // swipe: pointer events, so one path covers touch and pen, and the
  // mouse keeps the arrows to itself
  const stage = document.getElementById("lbStage");
  let sx = null, sy = null;
  stage.addEventListener("pointerdown", (e) => {
    if (e.pointerType === "mouse") return;
    sx = e.clientX;
    sy = e.clientY;
  });
  stage.addEventListener("pointerup", (e) => {
    if (sx === null) return;
    const dx = e.clientX - sx, dy = e.clientY - sy;
    sx = null;
    if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) nav(dx < 0 ? 1 : -1);
  });
  stage.addEventListener("pointercancel", () => { sx = null; });
})();

// Browsers without field-sizing grow the comment box by hand.
(function () {
  if (CSS.supports("field-sizing", "content")) return;
  const ta = document.querySelector("#comment-form textarea");
  if (!ta) return;
  const grow = () => {
    ta.style.height = "auto";
    ta.style.height = ta.scrollHeight + "px";
  };
  ta.addEventListener("input", grow);
  grow();
})();

// Share hands the page to the sheet the browser opens itself: the one
// on a phone, the one on a Mac. Nothing is loaded for it, and no other
// site hears of it.
//
// A browser without a sheet has nothing to offer, so there the word
// stays hidden and the foot keeps the two links it always had. The
// sheet only opens on a click, and a reader who dismisses it leaves an
// AbortError behind, which is not a failure and says nothing.
(function () {
  const button = document.getElementById("foot-share");
  if (!button || !navigator.share) return;
  button.hidden = false;
  button.addEventListener("click", () => {
    navigator.share({ title: document.title, url: location.href }).catch(() => {});
  });
})();

// The page says it: the script is up and its listeners stand. The
// gallery block says the same thing about its own half, and the
// browser tests wait for both before they act. Nothing on the page
// needs it; a reader who never gets this far reads the same words.
document.body.dataset.ready = "1";
