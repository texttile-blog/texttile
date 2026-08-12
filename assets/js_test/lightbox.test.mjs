import {test} from "node:test"
import assert from "node:assert/strict"
import {wrapIndex, swipeStep} from "../js/lightbox.js"

test("the row wraps around in both directions", () => {
  assert.equal(wrapIndex(0, 1, 3), 1)
  assert.equal(wrapIndex(2, 1, 3), 0)
  assert.equal(wrapIndex(0, -1, 3), 2)
  assert.equal(wrapIndex(0, -1, 1), 0)
})

test("a swipe pages once it is long enough and mostly horizontal", () => {
  assert.equal(swipeStep(-60, 5), 1) // dragging left goes forward
  assert.equal(swipeStep(60, 5), -1)
  assert.equal(swipeStep(-48, 0), 0) // the threshold itself is not past it
  assert.equal(swipeStep(-49, 0), 1)
  assert.equal(swipeStep(-60, -70), 0) // more vertical than horizontal: a scroll
})
