// The words the hooks say, in the language of the site.
//
// The gallery, the lightbox and the saved mark write their own text in
// the browser, so no template can carry it. The server renders the
// translations instead, as one JSON object in the page, out of the same
// catalogue as every other sentence (TexttileWeb.JsStrings). Nothing is
// fetched, and nothing here knows about languages.
//
// The English sentence is the key, exactly as a msgid is. So an English
// site carries an empty object, and a sentence nobody translated is
// said in English instead of showing a key.

const words = (() => {
  try {
    return JSON.parse(document.body.dataset.words || "{}")
  } catch {
    return {}
  }
})()

// t("Retry") gives the word. The second argument fills the %{name}
// places: t("%{count} on the way", {count: 3}).
export function t(source, vars) {
  let text = words[source] || source
  if (vars) {
    for (const name in vars) text = text.split(`%{${name}}`).join(vars[name])
  }
  return text
}

// Most of these sentences are built into markup, and a language that
// writes an apostrophe would end an attribute early. So the escaper
// travels with them.
export function esc(text) {
  return String(text).replace(
    /[&<>"']/g,
    c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"})[c]
  )
}
