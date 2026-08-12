import {test} from "node:test"
import assert from "node:assert/strict"
import {placeFixed} from "../js/place.js"

// A stub is enough: placeFixed only reads the anchor's rectangle and
// the element's wanted size, and writes style. No browser needed.
function el(want, width = 200) {
  return {offsetHeight: want, offsetWidth: width, style: {}}
}

function anchor(rect) {
  return {getBoundingClientRect: () => rect}
}

const viewport = {width: 1000, height: 600}

test("a menu that fits goes under its anchor", () => {
  const menu = el(200)
  placeFixed(menu, anchor({top: 40, bottom: 60, left: 10, right: 110}), "left", viewport)

  assert.equal(menu.style.top, "66px") // bottom + 6px gap
  assert.equal(menu.style.left, "10px")
  assert.equal(menu.style.right, "auto")
  assert.equal(menu.style.maxHeight, "")
})

test("a menu that does not fit below flips above when there is more room there", () => {
  const menu = el(300)
  placeFixed(menu, anchor({top: 500, bottom: 520, left: 10, right: 110}), "left", viewport)

  // above: 500 - 6 - 8 = 486 of room; it keeps its 300 and stands
  // with its foot at the anchor: top = 500 - 6 - 300
  assert.equal(menu.style.top, "194px")
  assert.equal(menu.style.maxHeight, "300px")
})

test("a menu too tall for either side is capped, never shorter than 120", () => {
  const menu = el(1000)
  placeFixed(menu, anchor({top: 60, bottom: 80, left: 10, right: 110}), "left", viewport)

  // below: 600 - 80 - 6 - 8 = 506; above is smaller, so it stays below
  assert.equal(menu.style.maxHeight, "506px")
  assert.equal(menu.style.top, "86px")
})

test("right alignment hangs the menu from the anchor's right edge", () => {
  const menu = el(100)
  placeFixed(menu, anchor({top: 40, bottom: 60, left: 700, right: 900}), "right", viewport)

  assert.equal(menu.style.right, "100px") // 1000 - 900
  assert.equal(menu.style.left, "auto")
})

test("left alignment never pushes the menu off either edge", () => {
  const wide = el(100, 400)
  placeFixed(wide, anchor({top: 40, bottom: 60, left: 900, right: 990}), "left", viewport)

  // 900 would put its right edge at 1300; it is held at width - 400 - 8
  assert.equal(wide.style.left, "592px")

  const cramped = el(100, 400)
  placeFixed(cramped, anchor({top: 40, bottom: 60, left: 2, right: 90}), "left", viewport)
  assert.equal(cramped.style.left, "8px")
})
