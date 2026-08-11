import {test} from "node:test"
import assert from "node:assert/strict"
import {tokensFrom, createUploads} from "../js/uploads.js"

/* -- the token grammar --------------------------------------------- */

test("the default token shapes are the strings Articles.Body reads", () => {
  const tk = tokensFrom(null)
  assert.equal(tk.up("a.jpg"), "![Uploading a.jpg…]()")
  assert.equal(tk.fail("a.jpg"), "![Upload failed: a.jpg]()")
  assert.equal(tk.done("pier.jpg", "/uploads/x/pier.jpg"), "![pier](/uploads/x/pier.jpg)")
})

test("server templates override the shapes, and the scanner follows", () => {
  const tk = tokensFrom({uploading: "Sending %{name} now", failed: "Lost: %{name}"})
  assert.equal(tk.up("a.jpg"), "![Sending a.jpg now]()")

  const used = tk.usedNames("x ![Sending a.jpg now]() y ![Lost: b.png]() z ![pier](/up/pier.jpg)")
  assert.deepEqual([...used].sort(), ["a.jpg", "b.png", "pier.jpg"])
})

/* -- the manager ---------------------------------------------------- */

/* a text area as a value: enough editor for the manager */
function fakeEditor(initial = "", readOnly = false) {
  let doc = initial
  const asked = []
  return {
    refused: asked,
    text: () => doc,
    readOnly: () => readOnly,
    refuse: () => asked.push(true),
    doc: () => doc,
    insert: text => { doc = doc === "" ? text : doc + "\n\n" + text },
    swap: (from, to) => {
      const at = doc.indexOf(from)
      if (at < 0) return false
      doc = doc.slice(0, at) + to + doc.slice(at + from.length)
      return true
    },
  }
}

/* an XMLHttpRequest that answers when told to */
function fakeRequests() {
  const open = []
  const mk = () => {
    const xhr = {
      listeners: {},
      upload: {addEventListener: (ev, fn) => (xhr.listeners["up:" + ev] = fn)},
      addEventListener: (ev, fn) => (xhr.listeners[ev] = fn),
      setRequestHeader: () => {},
      open: () => {},
      send: () => open.push(xhr),
      abort: () => (xhr.aborted = true),
      answer(status, body) {
        xhr.status = status
        xhr.responseText = body
        xhr.listeners.load()
      },
      progress(loaded, total) {
        xhr.listeners["up:progress"]({lengthComputable: true, loaded, total})
      },
    }
    return xhr
  }
  return {open, mk}
}

function build({doc = "", readOnly = false, templates = null} = {}) {
  const editor = fakeEditor(doc, readOnly)
  const requests = fakeRequests()
  const told = []
  const uploads = createUploads({
    tokens: tokensFrom(templates),
    uploadUrl: "/up",
    csrf: () => "token",
    maxMb: () => 1,
    editor,
    notify: state => told.push(state),
    request: requests.mk,
  })
  return {editor, requests, told, uploads}
}

// a real Blob, so the manager's FormData takes it in node too
const file = (name, size = 100) => Object.assign(new Blob(["x".repeat(size)]), {name})
const lastNews = told => told[told.length - 1].news

test("adding files writes tokens, says inserted, and runs two at a time", () => {
  const {editor, requests, told, uploads} = build()
  uploads.add([file("a.jpg"), file("b.jpg"), file("c.jpg")])

  assert.equal(editor.text(), "![Uploading a.jpg…]()\n\n![Uploading b.jpg…]()\n\n![Uploading c.jpg…]()")
  assert.deepEqual(lastNews(told), [{kind: "inserted", names: ["a.jpg", "b.jpg", "c.jpg"]}])
  assert.equal(requests.open.length, 2)

  requests.open[0].answer(200, JSON.stringify({url: "/uploads/x/a.jpg"}))
  assert.equal(requests.open.length, 3) // c starts when a settles
  assert.match(editor.text(), /!\[a\]\(\/uploads\/x\/a\.jpg\)/)
  assert.deepEqual(lastNews(told), [{kind: "done", name: "a.jpg"}])
})

test("a name the words already use is counted up, never reused", () => {
  const {editor, uploads} = build({doc: "![pier](/uploads/x/pier.jpg)"})
  uploads.add([file("pier.jpg")])

  assert.match(editor.text(), /!\[Uploading pier-2\.jpg…\]\(\)/)
})

test("progress crosses the seam as state, not as an event of its own", () => {
  const {requests, told, uploads} = build()
  uploads.add([file("a.jpg")])
  requests.open[0].progress(50, 100)

  const last = told[told.length - 1]
  assert.deepEqual(last.news, [])
  assert.deepEqual(last.files, [{name: "a.jpg", status: "uploading", pct: 50}])
})

test("a failure turns the token into the failure marker and keeps the file for retry", () => {
  const {editor, requests, told, uploads} = build()
  uploads.add([file("a.jpg")])
  requests.open[0].progress(70, 100)
  requests.open[0].answer(500, "")

  assert.match(editor.text(), /!\[Upload failed: a\.jpg\]\(\)/)
  assert.deepEqual(lastNews(told), [{kind: "failed", name: "a.jpg", pct: 70}])
  assert.deepEqual(told[told.length - 1].files, [{name: "a.jpg", status: "failed", pct: 70}])

  uploads.retry("a.jpg")
  assert.match(editor.text(), /!\[Uploading a\.jpg…\]\(\)/)
  assert.deepEqual(lastNews(told), [{kind: "retried", name: "a.jpg"}])
  assert.equal(requests.open.length, 2)
})

test("a 409 with a name means the picture is already in the entry: token gone, nothing failed", () => {
  const {editor, requests, told, uploads} = build({doc: "words"})
  uploads.add([file("copy.jpg")])
  requests.open[0].answer(409, JSON.stringify({of: "pier.jpg"}))

  // the token leaves; the blank line the insert drew is the editor's
  // own affair, exactly as in the browser
  assert.equal(editor.text().trim(), "words")
  assert.deepEqual(lastNews(told), [{kind: "refused", name: "copy.jpg", of: "pier.jpg"}])
  assert.deepEqual(told[told.length - 1].files, [])
})

test("a file over the roof never gets a token, and the news says so", () => {
  const {editor, told, uploads} = build()
  uploads.add([file("huge.mp4", 2 * 1024 * 1024)])

  assert.equal(editor.text(), "")
  assert.deepEqual(lastNews(told), [{kind: "too_big", names: ["huge.mp4"], roof: 1}])
})

test("removing takes the marker out; a retry without the file says so", () => {
  const {editor, requests, told, uploads} = build()
  uploads.add([file("a.jpg")])
  requests.open[0].answer(500, "")

  uploads.remove("a.jpg", "remove")
  assert.equal(editor.text(), "")
  assert.deepEqual(lastNews(told), [{kind: "removed", name: "a.jpg", how: "remove"}])

  uploads.retry("a.jpg")
  assert.deepEqual(lastNews(told), [{kind: "retry_missing", name: "a.jpg"}])
})

test("a read-only surface refuses instead of uploading", () => {
  const {editor, told, uploads} = build({readOnly: true})
  uploads.add([file("a.jpg")])

  assert.equal(editor.refused.length, 1)
  assert.equal(told.length, 0)
  assert.equal(editor.text(), "")
})
