import {test} from "node:test"
import assert from "node:assert/strict"
import {Gallery} from "../js/gallery_core.js"

function setup(t) {
  const images = []
  class Image {
    constructor() { images.push(this) }
  }
  const originalDocument = globalThis.document
  const originalImage = globalThis.Image
  globalThis.Image = Image
  globalThis.document = {createElement: () => new Image()}
  t.after(() => {
    globalThis.document = originalDocument
    globalThis.Image = originalImage
  })
  const art = {
    style: {}, children: [],
    querySelector(selector) { return selector === "img" ? this.children[0] : null },
    replaceChildren(...children) { this.children = children },
    setAttribute() {},
  }
  const state = {hidden: true, querySelector: () => ({addEventListener: (_event, fn) => { state.retry = fn }})}
  const core = Object.assign(Object.create(Gallery.prototype), {
    lb: {id: "1", token: 0, warmed: new Set()},
    root: {querySelector: selector => selector === "#lbImg" ? art : state},
    shownTiles: () => [1, 2, 3, 4].map(id => ({dataset: {
      id: String(id), full: `/max/${id}`, srcset: `/small/${id} 1320w, /max/${id} 2560w`,
      video: id === 2 ? "/film.mp4" : undefined,
    }})),
  })
  const data = {full: "/max/1", srcset: "/small/1 1320w, /max/1 2560w", filename: "one.jpg"}
  return {core, data, images, art, state}
}

test("the visible image loads in place before prefetching two pictures, never a film", t => {
  const {core, data, images, art} = setup(t)
  core.loadImage(data)
  assert.equal(art.children[0], images[0])
  assert.equal(images[0].srcset, data.srcset)
  assert.equal(images.length, 1)
  images[0].onload()
  assert.deepEqual(images.map(image => image.src), ["/max/1", "/max/2", "/max/3"])
  assert.equal(images[1].srcset, undefined)
  assert.equal(images[2].srcset, "/small/3 1320w, /max/3 2560w")
})

test("a load from a closed dialog cannot change a reopened dialog with the same token", t => {
  const {core, data, images, state} = setup(t)
  core.loadImage(data)
  core.lb = {id: "2", token: 1, loadingUrl: "/max/2", warmed: new Set()}
  images[0].onload()
  assert.equal(state.hidden, false)
  assert.equal(core.lb.loadingUrl, "/max/2")
  assert.equal(images.length, 1)
})

test("a failed image still warms its neighbours and retries the browser's chosen size", t => {
  const {core, data, images, art, state} = setup(t)
  core.loadImage(data)
  images[0].currentSrc = "http://localhost/small/1"
  images[0].onerror()
  assert.equal(images[0].hidden, true)
  assert.equal(state.hidden, false)
  assert.equal(images.length, 3)
  state.retry()
  const retry = art.children[0]
  assert.match(retry.src, /^http:\/\/localhost\/small\/1\?r=\d+$/)
  assert.equal(retry.srcset, undefined)
  retry.onload()
  assert.equal(state.hidden, true)
  assert.equal(images.length, 4)
})

test("rapid navigation ignores the previous load and a short gallery warms only its neighbour", t => {
  const {core, data, images} = setup(t)
  const tiles = core.shownTiles().slice(0, 2)
  core.shownTiles = () => tiles
  core.loadImage(data)
  core.lb.id = "2"
  core.loadImage({...data, full: "/max/2"})
  images[0].onload()
  assert.equal(core.lb.loadingUrl, "/max/2")
  assert.equal(images.length, 2)
  images[1].onload()
  assert.equal(images.length, 3)
  assert.equal(images[2].src, "/max/1")
})
