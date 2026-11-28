# Design

The visual rules of Texttile, and the log of the visual regressions that
taught them. `AGENTS.md` holds the product's promises (mobile first, light
pages, no repainting animations). This file holds the smaller rules that keep
a screen from looking broken.

Read it before a UI change. When you fix a visual regression, add its entry
to the log and its rule to the rules in the same pull request. A rule without
an entry is fine; an entry without a rule or a guard is not finished.

## Rules

1. **A row of words stands on one baseline.** A row that mixes links and
   buttons sets `align-items: baseline`. A grid or a flex parent can stretch
   the row taller than one line. A link then keeps its word on top, and a
   button centers its word, so the button drops.
2. **A button among links wears what the links wear.** Same font, same ink,
   no padding, no box. `base.css` resets every button. Do not give one back a
   box when it stands in a row of links.
3. **A separator stays outside the link.** Never draw a middle dot or other
   separator with `::before` or `::after` on an `<a>` or `<button>`. Hover
   underlines paint under inline pseudo-elements, focus rings wrap them, and
   clicking the dot activates the neighbour. Put the separator on a
   non-interactive wrapper (such as an `<li>`) or on a non-interactive
   neighbour instead.
4. **Focus state never shifts layout below the field.** A status indicator tied
   to `:focus` or `:focus-within` reserves its line height at rest so leaving
   the field on `mousedown` does not shift buttons below it out from under the
   pointer before `mouseup`.

## Verifying a screen

- **Show what a reader's browser shows.** Some elements appear only when the
  browser has a capability. Headless Chromium lacks some of them, so a test
  or a screenshot never sees these elements unless you give them to it.

  | Element | Shown when | Given to the tests by |
  |:---|:---|:---|
  | Share in the footer (`#foot-share`) | `navigator.share` exists | `TexttileWeb.E2E.a_share_sheet/1` |

  Every browser test gets these by default. A test about a browser without
  one opts out with its tag (`@tag :no_share_sheet`). In your own Playwright
  probe or `visual-qa` screenshot, add the same init script:

  ```js
  navigator.share = () => Promise.resolve()
  ```

  When you add an element of this kind, add its row to the table and its
  default to `TexttileWeb.E2E`.
- **Look at both layouts.** The reader band puts its columns side by side
  from 860px. Judge it at 390px and at 1000px or more.
- **Measure the text, not the box.** A stretched box has the same top as its
  neighbours even when its word stands lower. Measure the words with a
  `Range` (`range.selectNodeContents(el)`, then `getClientRects()`).
- **Hover interactive rows.** Static screenshots show resting state only.
  Hover every link and button in a changed row to verify that underlines,
  focus rings, and hit boxes stay on the word alone.

## Regressions

Newest first. One entry per regression: what a person saw, why, why nobody
saw it before, and what guards it now.

### 2026-11-28: Blurring the body editor shifted upload action buttons under the pointer

- **Seen:** clicking Remove all or Resume all in `#inlineResume` immediately
  after uploading images into the body did nothing.
- **Cause:** `.ed-foot .flag` switched from `display: inline-flex` to
  `display: none` when `.cm-content` lost focus on `mousedown`, collapsing
  `#edFoot` from 20px to 0px and moving `#inlineResume` upward before
  `mouseup` landed.
- **Missed because:** earlier padding and spacing around the editor left the
  pointer inside the button after the shift; tighter vertical rhythm exposed
  the jump.
- **Rule:** 4.
- **Guard:** `.ed-foot` reserves `min-height: 20px; line-height: 20px` at rest,
  and the browser tests "failed pictures in the text go again with one button"
  and "failed pictures in the text leave with one button" in
  `test/e2e/editor_flow_test.exs` exercise clicking `#inlineResume` straight
  from a focused body editor.

### 2026-11-27: Hovering footer links underlined the middle dot before them

- **Seen:** hovering Share or Sign in in the reader footer drew an underline
  under the middle dot before the word. The dot also sat inside the link's
  click and focus box. The same pattern existed on `.cmt-web` in the admin
  comments list.
- **Cause:** the separator came from `::before` on the `<a>` and `<button>`
  elements (`.band-out a + a::before`, `.band-out a + button::before`,
  `.band-out button + a::before`, and `.cmt-when + .cmt-web::before`). CSS
  `text-decoration` on `:hover` paints across inline pseudo-elements of the
  link or button. In addition, `button + a::before` drew a leading dot before
  Sign in when RSS was absent and Share was hidden.
- **Missed because:** earlier checks inspected resting layout and baseline
  alignment without hovering the items or checking pseudo-elements on links
  and buttons.
- **Rule:** 3.
- **Guard:** the browser tests "keeps footer separators outside the links
  and buttons" and "shows no leading separator when Sign in stands alone" in
  `test/e2e/public_site_flow_test.exs`, plus the `.cmt-web` check in
  `test/e2e/comments_flow_test.exs`.

### 2026-11-24: Share stood lower than the footer links (#131)

- **Seen:** on a wide screen, Share in the reader footer stood about 8px
  lower than RSS and Sign in.
- **Cause:** from 860px the band's grid stretched the footer row to 40px.
  The links kept their words on top, and the Share button centered its word.
- **Missed because:** headless Chromium has no `navigator.share`, so Share
  was hidden in every test and screenshot.
- **Rule:** 1.
- **Guard:** the browser test "keeps Share on the line of the links beside
  it" and the default share sheet in `TexttileWeb.E2E`.
