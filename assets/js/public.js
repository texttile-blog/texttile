// The public site's whole script: the view counter, the search jump,
// and the lightbox of the reader gallery. Every page works without it;
// the tiles are plain links to the full pictures until this runs.

// The lightbox shell is server-rendered (article.html.heex), so the
// page stands whole without a script; the behaviour on it is the one
// lightbox every surface shares.
import {wrapIndex, attachSwipe, mediaNode, trapTab, quiet} from "./lightbox.js";
import {commentMoment} from "./moment.js";

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

// The day under each comment gets its hour, in the reader's zone.
document.querySelectorAll("time[data-comment-moment]").forEach((el) => {
  el.textContent = commentMoment(new Date(el.dateTime), document.documentElement.lang);
});

// The search field of the text list. An empty field means the whole
// list, whichever way it was emptied.
//
// A form only speaks when it is submitted, and none of the three ways
// out of a search term submits one: the browser's own clear cross
// fires `search`, Escape fires nothing, and a held backspace fires
// `input`. So the list stayed filtered under a field that read empty,
// and the words the reader had deleted went on deciding what they saw.
//
// The whole address goes, not only the term: the field searches every
// year, and the year beside it narrows what the field found. With no
// term there is nothing to narrow.
(function () {
  const field = document.getElementById("q");
  if (!field) return;
  const list = field.form.getAttribute("action") || location.pathname;
  let wait = null;

  // A moment's grace, so clearing the field to type something else
  // does not throw the reader back to the top of the list first.
  function clearedNow() {
    if (field.value.trim() !== "" || location.search === "") return;
    location.href = list;
  }

  function cleared() {
    clearTimeout(wait);
    if (field.value.trim() !== "") return;
    wait = setTimeout(clearedNow, 250);
  }

  field.addEventListener("input", cleared);
  field.addEventListener("search", cleared);

  // The year and the month are choices on the same form, and a choice
  // is an answer: it goes as soon as it is made, with whatever stands
  // in the field.
  field.form.addEventListener("change", (e) => {
    if (e.target.tagName !== "SELECT") return;
    // a month belongs to the year it was picked in; a new year starts whole
    const month = document.getElementById("month");
    if (e.target.id === "year" && month) month.value = "";
    field.form.requestSubmit();
  });

  // "/" jumps into the field from anywhere on the page; Escape empties
  // it, which is one of the three ways above.
  addEventListener("keydown", (e) => {
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
    const el = document.activeElement;
    const typing = el && ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);

    if (e.key === "/" && !typing) {
      e.preventDefault();
      field.focus();
      field.select();
    } else if (e.key === "Escape" && el === field && el.value) {
      el.value = "";
      cleared();
    }
  });
})();

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
    at = wrapIndex(i, 0, tiles.length);
    const tile = tiles[at];
    const inner = tile.querySelector("img");
    const caption = tile.dataset.caption || (inner && inner.alt) || "";

    const art = document.getElementById("lbArt");
    art.replaceChildren(
      tile.dataset.video
        ? mediaNode({film: tile.dataset.video, poster: tile.dataset.full, caption}, playing)
        : mediaNode({src: tile.dataset.full || tile.href, srcset: tile.dataset.srcset, caption}, false)
    );
    document.getElementById("lbCount").textContent = at + 1 + " / " + tiles.length;
    document.getElementById("lbCap").textContent = caption;

    // The next ones come in once this one is there, not beside it: on
    // a slow line the picture on show is the one that must not wait.
    // A picture that fails is no reason to keep the next ones waiting.
    const shown = art.querySelector("img");
    if (shown && !shown.complete) {
      shown.addEventListener("load", () => warm(at), {once: true});
      shown.addEventListener("error", () => warm(at), {once: true});
    } else {
      warm(at);
    }
  }

  // The two pictures after the one on show are fetched ahead, so a
  // page forward on a slow line finds them in the cache. A film is
  // never fetched ahead; its poster is a picture and is. The
  // wrap-around stops at the picture on show, so a short row warms
  // only what it has. The warming picture is built the way the shown
  // one is, so the browser picks the same size and the cache hits.
  const warmed = new Set();
  function warm(i) {
    for (const step of [1, 2]) {
      const tile = tiles[wrapIndex(i, step, tiles.length)];
      if (tile === tiles[i]) break;
      const src = tile.dataset.full || tile.href;
      if (warmed.has(src)) continue;
      warmed.add(src);
      mediaNode({src, srcset: tile.dataset.srcset}, false);
    }
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
    quiet(document.getElementById("lbArt"));
    lb.hidden = true;
    document.documentElement.classList.remove("lb-open");
    if (at >= 0) tiles[at].focus();
  }

  // A plain click opens the lightbox; a click with a modifier (or the
  // middle button) stays the link it looks like and fetches the
  // original in its own tab.
  function openOn(link, i) {
    link.addEventListener("click", (e) => {
      if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      e.preventDefault();
      open(i);
    });
  }
  tiles.forEach(openOn);

  // The square at the head of the text is one of the tiles shown
  // again: it opens the lightbox on that tile, not on a copy of it.
  const hero = document.getElementById("preview");
  const heroAt = hero ? tiles.findIndex((tile) => tile.href === hero.href) : -1;
  if (heroAt >= 0) openOn(hero, heroAt);
  document.getElementById("lbClose").addEventListener("click", close);
  document.getElementById("lbPrev").addEventListener("click", () => nav(-1));
  document.getElementById("lbNext").addEventListener("click", () => nav(1));
  // The dark is a way out. What stands on it is not: the picture, the
  // film and its controls, the buttons, and the caption a reader may
  // be selecting. The picture's box is as wide as the stage, so a
  // click in the dark beside the picture lands on the box, and it
  // counts as the dark.
  lb.addEventListener("click", (e) => {
    if (e.target.closest("img, video, button, a, .lb-cap")) return;
    close();
  });

  addEventListener("keydown", (e) => {
    if (lb.hidden) return;
    if (e.key === "Escape") close();
    else if (e.key === "ArrowLeft") { e.preventDefault(); nav(-1); }
    else if (e.key === "ArrowRight") { e.preventDefault(); nav(1); }
  });

  attachSwipe(document.getElementById("lbStage"), nav);
  trapTab(lb);
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
