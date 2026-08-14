import {test} from "node:test"
import assert from "node:assert/strict"
import {readTheLine} from "../js/connection.js"

// A page that is live and was answered a moment ago.
const standing = (overrides = {}) => ({
  transport: "WebSocket",
  connected: true,
  clean: false,
  joined: true,
  live: true,
  inFront: true,
  silent: 2000,
  ...overrides,
})

test("a line that answers wears no mark", () => {
  const read = readTheLine(standing())
  assert.equal(read.mark, "never")
  assert.equal(read.revive, false)
  assert.equal(read.note, "WebSocket · joined · answered 2s ago")
})

test("a line that looks fine and answers nothing is said at once and built again", () => {
  const read = readTheLine(standing({silent: 9000}))
  assert.equal(read.mark, "now")
  assert.equal(read.revive, true)
  assert.equal(read.note, "WebSocket · joined · quiet for 9s")
})

test("a line that was put down on purpose is left alone", () => {
  const read = readTheLine(standing({clean: true, connected: false, live: false, silent: 30_000}))
  assert.equal(read.mark, "soon")
  assert.equal(read.revive, false)
})

test("a tab in the background is not judged by its silence", () => {
  // its clock ran slowly while it sat there, so the silence it brings
  // says nothing about the line
  const read = readTheLine(standing({inFront: false, silent: 60_000}))
  assert.equal(read.mark, "never")
  assert.equal(read.revive, false)
})

test("a socket that stands without a view that answers is not standing", () => {
  const read = readTheLine(standing({joined: false}))
  assert.equal(read.mark, "soon")
  assert.equal(read.revive, false)
  assert.match(read.note, /not joined/)
})

test("a page that has never been live waits before it says so", () => {
  const read = readTheLine(standing({connected: false, live: false, silent: 1000}))
  assert.equal(read.mark, "soon")
  assert.equal(read.revive, false)
})

test("the mark names the transport, so a report needs no console", () => {
  assert.match(readTheLine(standing({transport: "LongPoll"})).note, /^LongPoll/)
})
