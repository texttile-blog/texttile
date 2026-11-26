defmodule TexttileWeb.E2E do
  @moduledoc """
  The way into a browser test.

  `use TexttileWeb.E2E` and the test starts from a clean installation
  with one admin in it, a browser context that closes with the test,
  and nothing left over from the test before. AGENTS.md asks browser
  tests to enter screens through these helpers and wait for the live
  page; that rule used to be broken 39 times, because the helper was
  too thin to make following it easier than not.

  Three doors, one per kind of page, and each waits for what that page
  has to have before a test may act on it:

    * `open/2` for a screen of the admin area, which is a LiveView
    * `open_editor/2` for the editor, which also waits for the gallery
    * `open_page/2` for a reader page, whose script says when it stands

  `Fluffy.visit/2` is for the pages that carry neither: the
  sign-in screens and a link out of a mail. Say so where you use it.

  `eventually/2` comes along for the things that settle a moment after
  the click.
  """

  use ExUnit.CaseTemplate

  import Fluffy
  import Fluffy.Assert, only: [assert_has: 2, poll: 2]
  import Fluffy.Locator

  # Not async, the default: SQLite serializes writers, concurrent
  # sandbox owners flake.
  using do
    quote do
      use Playwright.Test
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator
      import Fluffy.Playwright
      import Texttile.AccountsFixtures
      import Texttile.ArticlesFixtures
      import Texttile.DataCase, only: [eventually: 1, eventually: 2]
      import TexttileWeb.E2E

      @moduletag :e2e

      setup {TexttileWeb.E2E, :sandbox_and_browser}
      setup {TexttileWeb.E2E, :one_admin_to_sign_in_as}
      setup {TexttileWeb.E2E, :a_share_sheet}
    end
  end

  @doc """
  Starts the sandbox owner, then the browser session as `:conn`.

  Fluffy closes the session's browser context in an `on_exit` of its
  own, registered after the owner's, so the context is gone before the
  owner stops and no LiveView of this test reconnects under a dead one.
  """
  def sandbox_and_browser(tags) do
    Texttile.DataCase.setup_sandbox(tags)
    %{conn: start_session(:playwright)}
  end

  @doc """
  The admin every browser test signs in as, in the context as `:kb`.

  `sign_in/1` signs this one in. A test that needs a second person
  makes it itself. A test about the way a blog with nobody in it takes
  its first admin says `@moduletag :nobody_signed_up` and gets none.
  """
  def one_admin_to_sign_in_as(%{nobody_signed_up: true}), do: :ok

  def one_admin_to_sign_in_as(_context) do
    %{kb: Texttile.AccountsFixtures.user_fixture(%{email: "kb@example.org", display_name: "kb"})}
  end

  @doc """
  Gives the browser a share sheet, the way a phone and a Mac have one.

  Headless Chromium has none, so without this the footer's Share stays
  hidden in every test and every screenshot, and nobody sees how it
  stands beside the links. That is how a misaligned Share reached a
  reader (DESIGN.md). The sheet notes what it was handed in
  `window.__shared`. A test about a browser without a sheet says
  `@tag :no_share_sheet`.
  """
  def a_share_sheet(%{no_share_sheet: true}), do: :ok

  def a_share_sheet(%{conn: conn}) do
    Fluffy.Playwright.add_init_script(
      conn,
      "navigator.share = (data) => { window.__shared = data; return Promise.resolve() }"
    )

    :ok
  end

  @doc """
  Waits until the page in the browser is a live one.

  The server answers a LiveView with a dead render first, and the
  script picks it up a moment later. Playwright acts as soon as an
  element stands in the DOM, so a click can land in that moment: the
  button is there, nothing listens, and no error says so. The test
  then waits for a result that can never come.

  A developer machine hides this, because the script is up before the
  first click. A loaded CI runner does not.

  Fluffy waits for this itself after a visit and after a navigation a
  step of the test causes, so only a socket the test connects by hand
  needs it.
  """
  def await_live(session) do
    assert_has(session, by_css("[data-phx-main].phx-connected"))
  end

  @doc """
  Opens a screen of the admin area, live: Fluffy's visit waits for its
  LiveView to connect. The one way into a screen that carries a LiveView.
  """
  def open(session, path) do
    visit(session, path)
  end

  @doc """
  Opens a reader page and waits for its script to stand.

  A reader page carries no LiveView, so there is no `phx-connected` to
  wait for. It carries `public.js`, which says so on the body when its
  listeners are up: the search jump, the lightbox and the counter are
  not there before that. A test that presses a key on a reader page
  races the script without this.
  """
  def open_page(session, path) do
    session |> visit(path) |> assert_has(by_css("body[data-ready]"))
  end

  @doc """
  Opens the editor of a text and waits for the tiles to be usable.

  The gallery's client half is a chunk of its own, fetched after the
  page is live. Until it is there the file input has no listener, so a
  picked file is lost in silence. The block says so itself: it wears
  `data-ready` from the moment its half is alive.
  """
  def open_editor(session, article_id) do
    session
    |> open("/admin/texts/#{article_id}")
    |> assert_has(by_css("#tilesBlock[data-ready]"))
  end

  @doc """
  Signs kb in and lands in the admin area, live.

  Every browser test starts here. Fluffy follows the sign-in to the
  admin area and waits for its LiveView to connect.
  """
  def sign_in(session) do
    session
    |> visit("/login")
    |> fill(by_label("Email address"), "kb@example.org")
    |> fill(by_label("Password"), Texttile.AccountsFixtures.valid_password())
    |> click(by_role(:button, name: "Sign in"))
    |> assert_has(by_css("#new-text"))
  end

  @doc """
  Ages a public form's invisible stamp, so the test can submit faster
  than a person types without reading as a script.

  The time trap is always on and has no configuration; a test stands on
  its far side by handing the page a stamp that was drawn ten seconds
  ago, minted by the same module that judges it. `form` is
  `{:comment, article.id}` or `:newsletter`.
  """
  def age_form(session, form) do
    stamp = TexttileWeb.HumanCheck.stamp(form, now: System.system_time(:second) - 10)

    run_script(
      session,
      "t => document.querySelectorAll(\"input[name='t']\").forEach(el => el.value = t)",
      stamp
    )
  end

  @doc """
  Runs a script in the page for what it does there, such as a stand-in
  for the network, and goes on with the session.

  A script whose answer the test checks goes through `assert_script/4`
  instead, which waits for the page to come round.
  """
  def run_script(session, script, arg \\ nil) do
    Fluffy.Playwright.evaluate(session, script, arg)
    session
  end

  @doc """
  Checks what a script in the page returns, and asks again until
  `check` passes or the expect timeout runs out.

  For what no locator assertion reads: a measure of the layout, a
  count the page keeps in a variable. The script runs once per try,
  so it only looks.
  """
  def assert_script(session, script, arg \\ nil, check) do
    Fluffy.Assert.assert(session, poll(&Fluffy.Playwright.evaluate(&1, script, arg), check))
  end

  @doc """
  A draft with a title and some words, for a test whose subject is
  something else: the gallery, a film, the language of the screen.
  """
  def draft!(user, title \\ "A text", body \\ "Plain words.") do
    {:ok, article} = Texttile.Articles.create_draft(user)
    {:ok, article} = Texttile.Articles.update_text(article, %{title: title, body: body})
    article
  end
end
