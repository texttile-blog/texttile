import {test} from "node:test"
import assert from "node:assert/strict"
import {sendChunks, CHUNK} from "../js/chunks.js"

/* an XMLHttpRequest that answers when told to, and keeps what it was
   given, so a test can read the pieces. The sender speaks through the
   handler properties, so the fake calls those. */
function fakeRequests() {
  const sent = []
  const mk = () => {
    const xhr = {
      upload: {onprogress: null, onload: null},
      headers: {},
      setRequestHeader: (name, value) => (xhr.headers[name] = value),
      open: (method, withUrl) => (xhr.url = withUrl),
      send: body => {
        xhr.body = body
        sent.push(xhr)
      },
      abort: () => {
        if (xhr.onabort) xhr.onabort()
      },
      answer(status, body) {
        xhr.status = status
        xhr.responseText = body ?? ""
        if (xhr.onload) xhr.onload()
      },
      drop() {
        if (xhr.onerror) xhr.onerror()
      },
      uploaded() {
        if (xhr.upload.onload) xhr.upload.onload()
      },
      progress(loaded, total) {
        if (xhr.upload.onprogress) xhr.upload.onprogress({lengthComputable: true, loaded, total})
      },
    }
    return xhr
  }
  return {sent, mk}
}

/* a file of `size` bytes that knows its slices */
function fakeFile(size) {
  return {size, slice: (start, end) => `bytes ${start}..${end}`, type: "image/jpeg"}
}

test("a small file is one request, and its answer is the upload's", () => {
  const requests = fakeRequests()
  const answers = []
  const uploaded = []
  sendChunks({
    url: "/admin/texts/5/gallery/chunks",
    csrf: "the-token",
    file: fakeFile(1000),
    name: "Pier.jpg",
    request: requests.mk,
    onUploaded: () => uploaded.push(true),
    onAnswer: answer => answers.push(answer),
  })

  assert.equal(requests.sent.length, 1)
  const xhr = requests.sent[0]
  assert.match(xhr.url, /upload=[0-9a-f]{16}/)
  assert.match(xhr.url, /index=0/)
  assert.match(xhr.url, /parts=1/)
  assert.match(xhr.url, /size=1000/)
  assert.match(xhr.url, /name=Pier\.jpg/)
  assert.equal(xhr.headers["x-csrf-token"], "the-token")
  assert.equal(xhr.body, "bytes 0..1000")

  /* the browser fires the upload's own load (all bytes out) before the
     answer arrives */
  xhr.uploaded()
  xhr.answer(200, `{"id":"7"}`)
  assert.deepEqual(answers, [{status: 200, response: {id: "7"}}])
  assert.deepEqual(uploaded, [true], "the bytes were out the door first")
})

test("a big file leaves in ordered pieces, and the last answer wins", () => {
  const requests = fakeRequests()
  const answers = []
  const size = CHUNK * 2 + 500
  sendChunks({
    url: "/up/chunks",
    csrf: "t",
    file: fakeFile(size),
    name: "a.jpg",
    request: requests.mk,
    onAnswer: answer => answers.push(answer),
  })

  assert.equal(requests.sent.length, 1)
  requests.sent[0].answer(204)
  assert.equal(requests.sent.length, 2)
  assert.match(requests.sent[1].url, /index=1/)
  requests.sent[1].answer(204)
  assert.equal(requests.sent.length, 3)
  assert.match(requests.sent[2].url, /index=2/)
  assert.equal(requests.sent[2].body, `bytes ${CHUNK * 2}..${size}`)

  requests.sent[2].answer(200, `{"id":"9"}`)
  assert.deepEqual(answers, [{status: 200, response: {id: "9"}}])
})

test("a piece that is refused ends the upload with that answer", () => {
  const requests = fakeRequests()
  const answers = []
  sendChunks({
    url: "/up/chunks",
    csrf: "t",
    file: fakeFile(CHUNK * 3),
    name: "a.jpg",
    request: requests.mk,
    onAnswer: answer => answers.push(answer),
  })

  requests.sent[0].answer(204)
  requests.sent[1].answer(409, `{"error":"already","of":"a.jpg"}`)
  assert.deepEqual(answers, [{status: 409, response: {error: "already", of: "a.jpg"}}])
  assert.equal(requests.sent.length, 2, "no piece after the refusal")
})

test("progress counts the file, not the piece", () => {
  const requests = fakeRequests()
  const seen = []
  sendChunks({
    url: "/up/chunks",
    csrf: "t",
    file: fakeFile(CHUNK * 2),
    name: "a.jpg",
    request: requests.mk,
    onProgress: done => seen.push(done),
  })

  requests.sent[0].progress(300, CHUNK)
  assert.deepEqual(seen, [300])
  requests.sent[0].progress(CHUNK, CHUNK)
  assert.deepEqual(seen, [300, CHUNK])
  requests.sent[0].answer(204)

  requests.sent[1].progress(400, CHUNK)
  assert.deepEqual(seen, [300, CHUNK, CHUNK + 400])
})

test("a piece that never became an answer is a loss", () => {
  const requests = fakeRequests()
  const answers = []
  const losses = []
  sendChunks({
    url: "/up/chunks",
    csrf: "t",
    file: fakeFile(CHUNK * 2),
    name: "a.jpg",
    request: requests.mk,
    onAnswer: answer => answers.push(answer),
    onLost: loss => losses.push(loss),
  })

  requests.sent[0].drop()
  assert.deepEqual(losses.length, 1)
  assert.notEqual(losses[0].xhr, null)
  assert.deepEqual(answers, [])
  assert.equal(requests.sent.length, 1, "no piece after a lost one")
})

test("abort takes the piece in the air down and loses quietly", () => {
  const requests = fakeRequests()
  const losses = []
  const sender = sendChunks({
    url: "/up/chunks",
    csrf: "t",
    file: fakeFile(CHUNK * 2),
    name: "a.jpg",
    request: requests.mk,
    onLost: loss => losses.push(loss),
  })

  sender.abort()
  assert.deepEqual(losses, [{aborted: true}])
})

test("a name with marks and spaces arrives readable in the query", () => {
  const requests = fakeRequests()
  sendChunks({
    url: "/up/chunks",
    csrf: "t",
    file: fakeFile(10),
    name: "Hafen & Kran (1).jpg",
    request: requests.mk,
  })

  /* URLSearchParams speaks the form encoding, where a space is a plus;
     the server's query reader reads the same language */
  assert.match(requests.sent[0].url, /name=Hafen\+%26\+Kran\+%281%29\.jpg/)
})
