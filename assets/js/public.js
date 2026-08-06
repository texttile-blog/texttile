// The public site's whole script: the search jump, and the lightbox of
// the reader gallery. Every page works without it; the tiles are plain
// links to the full pictures until this runs.

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
(function () {
  const gal = document.getElementById("gal");
  const lb = document.getElementById("lb");
  if (!gal || !lb) return;

  const tiles = [...gal.querySelectorAll("a")];
  let at = -1;

  function show(i) {
    at = (i + tiles.length) % tiles.length;
    const tile = tiles[at];
    const img = document.createElement("img");
    img.src = tile.href;
    img.alt = tile.dataset.caption || "";
    const art = document.getElementById("lbArt");
    art.replaceChildren(img);
    document.getElementById("lbCount").textContent = at + 1 + " / " + tiles.length;
    document.getElementById("lbCap").textContent = tile.dataset.caption || "";
  }

  function open(i) {
    show(i);
    lb.hidden = false;
    document.documentElement.classList.add("lb-open");
    document.getElementById("lbClose").focus();
  }

  function nav(dir) {
    if (!lb.hidden) show(at + dir);
  }

  function close() {
    lb.hidden = true;
    document.documentElement.classList.remove("lb-open");
    if (at >= 0) tiles[at].focus();
  }

  tiles.forEach((tile, i) =>
    tile.addEventListener("click", (e) => {
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
