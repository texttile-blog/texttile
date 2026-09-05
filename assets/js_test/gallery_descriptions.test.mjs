import {test} from "node:test"
import assert from "node:assert/strict"
import {Gallery} from "../js/gallery_core.js"

function gallery(pushEvent) {
  return Object.assign(Object.create(Gallery.prototype), {
    hook: {pushEvent},
    pendingDescriptions: new Map(),
    descriptionSaves: new Set(),
    offline: false,
  })
}

test("failed descriptions survive a reconnect, including edits on another tile", async () => {
  const saved = []
  const core = gallery(async (_event, value) => {
    if (core.offline) throw new Error("disconnected")
    saved.push(value)
    return {ok: true}
  })
  core.offline = true
  core.pendingDescriptions.set("1", {id: "1", description: "The coast"})
  await core.saveDescription()
  core.pendingDescriptions.set("2", {id: "2", description: "The lake"})
  await core.saveDescription()
  assert.equal(core.pendingDescriptions.size, 2)
  assert.equal(core.descriptionSaves.size, 0)

  core.offline = false
  await core.saveDescription()
  assert.deepEqual(saved, [
    {id: "1", description: "The coast"},
    {id: "2", description: "The lake"},
  ])
  assert.equal(core.pendingDescriptions.size, 0)
  assert.equal(core.descriptionSaves.size, 0)
})

test("an older reply does not discard a newer description", async () => {
  const replies = []
  const saved = []
  const core = gallery((_event, value) => {
    saved.push(value.description)
    return new Promise(resolve => replies.push(resolve))
  })
  core.pendingDescriptions.set("1", {id: "1", description: "First"})
  const first = core.saveDescription()
  core.pendingDescriptions.set("1", {id: "1", description: "Second"})
  await core.saveDescription()
  assert.deepEqual(saved, ["First"])
  replies.shift()({ok: true})
  await first
  assert.equal(core.pendingDescriptions.get("1").description, "Second")
  assert.deepEqual(saved, ["First", "Second"])
  replies.shift()({ok: true})
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(core.pendingDescriptions.size, 0)
  assert.equal(core.descriptionSaves.size, 0)
})
