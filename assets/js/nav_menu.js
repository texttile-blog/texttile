/* THE WORDMARK MENU · positioned fixed and placed by placeFixed, so no
   scroll container, no overflow and no stacking context can ever clip
   it. Beside it live the two other whole-document behaviours of the
   admin shell: the password reveal, and the key digits.

   THE KEY DIGITS · a digit jumps to its section from anywhere in the
   admin area. The keys sleep while you are typing in a field, and each
   digit only works once its section exists: a section row in the
   wordmark menu carries its digit as data-key. */

import {placeFixed} from "./place.js"

const menuEl = () => document.getElementById("navMenu")
const wmBtn = () => document.getElementById("wmBtn")

function toggleMenu() {
  const menu = menuEl()
  if (!menu) return
  if (menu.hidden) {
    menu.hidden = false
    wmBtn().setAttribute("aria-expanded", "true")
    placeFixed(menu, wmBtn(), "left")
  } else {
    closeMenu()
  }
}

function closeMenu() {
  const menu = menuEl()
  if (!menu || menu.hidden) return
  menu.hidden = true
  const btn = wmBtn()
  if (btn) btn.setAttribute("aria-expanded", "false")
}

function typingIn(el) {
  return el && (el.isContentEditable ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName))
}

export function initNavMenu() {
  document.addEventListener("click", event => {
    /* a control that rewrote its own row is out of the document by the
       time the click arrives here. A detached target must not read as
       "somewhere outside the menu". */
    if (!event.target.isConnected) return

    if (event.target.closest("#wmBtn")) {
      toggleMenu()
      return
    }

    const toggle = event.target.closest("[data-toggle-password]")
    if (toggle) {
      const input = document.getElementById(toggle.dataset.togglePassword)
      if (input) {
        const show = input.type === "password"
        input.type = show ? "text" : "password"
        toggle.textContent = show ? "Hide" : "Show"
        input.focus()
      }
      return
    }

    if (!event.target.closest("#navMenu")) closeMenu()
  })

  document.addEventListener("keydown", event => {
    if (event.key === "Escape") {
      closeMenu()
      return
    }
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (typingIn(event.target)) return
    if (event.key === "/") {
      const search = document.querySelector("#grid-search input")
      if (search) {
        event.preventDefault()
        search.focus()
      }
      return
    }
    if (!/^[0-9]$/.test(event.key)) return
    const row = document.querySelector(`#navMenu [data-key="${event.key}"]`)
    if (row) {
      closeMenu()
      row.click()
    }
  })

  window.addEventListener("resize", () => {
    const menu = menuEl()
    if (menu && !menu.hidden) placeFixed(menu, wmBtn(), "left")
  })
}
