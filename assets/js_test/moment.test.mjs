import {test} from "node:test"
import assert from "node:assert/strict"
import {commentMoment} from "../js/moment.js"

const now = new Date("2026-10-29T12:00:00Z")

test("a comment gets its hour in the reader's zone", () => {
  const at = new Date("2026-10-29T13:05:00Z")
  assert.equal(commentMoment(at, "de", now, "Europe/Berlin"), "29. Oktober um 14:05")
  assert.equal(commentMoment(at, "en", now, "Europe/Berlin"), "29 October at 14:05")
})

test("the day follows the reader's zone across midnight", () => {
  const at = new Date("2026-10-29T23:30:00Z")
  assert.equal(commentMoment(at, "de", now, "Europe/Berlin"), "30. Oktober um 00:30")
})

test("a comment of another year carries the year", () => {
  const at = new Date("2025-07-02T08:00:00Z")
  assert.equal(commentMoment(at, "de", now, "Europe/Berlin"), "2. Juli 2025 um 10:00")
})
