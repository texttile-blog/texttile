import {test} from "node:test"
import assert from "node:assert/strict"
import {t, esc} from "../js/i18n.js"

// Outside a browser there is no catalogue, so every sentence is said
// in English - exactly what an untranslated site does.

test("an untranslated sentence is said as it is", () => {
  assert.equal(t("Retry"), "Retry")
})

test("the places are filled, every occurrence of them", () => {
  assert.equal(t("%{count} of %{count} done", {count: 3}), "3 of 3 done")
  assert.equal(t("Tile %{index}, %{file}", {index: 2, file: "a.jpg"}), "Tile 2, a.jpg")
})

test("esc neuters everything that could end an attribute early", () => {
  assert.equal(esc(`<a href="x" title='y'> & more`),
    "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt; &amp; more")
  assert.equal(esc(42), "42")
})
