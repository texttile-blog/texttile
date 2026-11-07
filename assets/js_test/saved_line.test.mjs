import {test} from "node:test"
import assert from "node:assert/strict"
import {savedLine, toastLine} from "../js/saved_ticker.js"

// the identity catalogue: keys come back as sentences, places filled
const t = (source, vars) => {
  let text = source
  if (vars) for (const name in vars) text = text.split(`%{${name}}`).join(vars[name])
  return text
}

// 12:34:56 local time on an arbitrary day
const at = new Date(2026, 7, 11, 12, 34, 56).getTime()

const line = (overrides = {}) => savedLine({at, now: at + 5000, wide: true, ...overrides}, t)

test("the toast says Saved with a tick, and the exact second lives in the tooltip", () => {
  assert.deepEqual(toastLine({now: at, note: "", noteUntil: 0}, t), {text: "Saved", ms: 2600, tick: true})
  assert.equal(line().title, "The last save was at 12:34:56.")
})

test("a note is a sentence to read and takes the toast for as long as it stands", () => {
  const {text, ms, tick} = toastLine({now: at, note: "The address was taken", noteUntil: at + 4600}, t)
  assert.equal(text, "The address was taken")
  assert.equal(ms, 4600)
  assert.equal(tick, false)
})

test("a spent note gives the toast back to the plain word", () => {
  assert.equal(toastLine({now: at + 5000, note: "Restored", noteUntil: at + 1000}, t).text, "Saved")
})

test("a fresh save reads as Saved, an old one with its clock time", () => {
  assert.equal(line({now: at + 19_000}).text, "Saved")
  assert.equal(line({now: at + 21_000}).text, "Saved 12:34")
})

test("a phone bar and a desk bar say the same stamp", () => {
  for (const wide of [true, false]) {
    assert.equal(line({wide, now: at + 5000}).text, "Saved")
    assert.equal(line({wide, now: at + 60_000}).text, "Saved 12:34")
  }
})

test("the clock pads its digits", () => {
  const early = new Date(2026, 7, 11, 9, 5, 7).getTime()
  const {text, title} = line({at: early, now: early + 60_000})
  assert.equal(text, "Saved 09:05")
  assert.equal(title, "The last save was at 09:05:07.")
})
