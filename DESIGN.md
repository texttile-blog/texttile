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

## Regressions

Newest first. One entry per regression: what a person saw, why, why nobody
saw it before, and what guards it now.

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
