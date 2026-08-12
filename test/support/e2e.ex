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

  `PhoenixTest.visit/2` is for the pages that carry neither: the
  sign-in screens and a link out of a mail. Say so where you use it.

  `eventually/2` comes along for the things that settle a moment after
  the click.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Not async: SQLite serializes writers, concurrent sandbox owners flake.
      use PhoenixTest.Playwright.Case, async: false

      import Texttile.AccountsFixtures
      import Texttile.ArticlesFixtures
      import Texttile.DataCase, only: [eventually: 1, eventually: 2]
      import TexttileWeb.E2E

      @moduletag :e2e

      setup {TexttileWeb.E2E, :close_browser_context_afterwards}
      setup {TexttileWeb.E2E, :one_admin_to_sign_in_as}
    end
  end

  @doc """
  Closes the test's browser context the moment the test ends, before
  the next one starts, and clears what no sandbox rolls back.

  The Playwright case closes contexts in a spawned process, so a page
  can outlive its test. Its LiveViews then reconnect mid-run under a
  sandbox owner that is already dead, and SQLite's single writer turns
  that race into stalls in whatever test runs next. Registered after
  the case's own setup, this runs first on exit and closes the context
  synchronously.
  """
  def close_browser_context_afterwards(%{conn: conn}) do
    # The browser tests keep their own sandbox, so they never pass
    # through Texttile.DataCase.setup_sandbox/1. They open editors and
    # upload files like nobody else, and both outlive them the same
    # way, so they start from none too.
    Texttile.DataCase.clear_what_no_sandbox_rolls_back()

    ExUnit.Callbacks.on_exit(fn ->
      try do
        PlaywrightEx.BrowserContext.close(conn.context_id, timeout: 5_000)
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  @doc """
  The admin every browser test signs in as, in the context as `:kb`.

  `sign_in/1` signs this one in. A test that needs a second person
  makes it itself. A test about the way a blog with nobody in it takes
  its first admin says `@moduletag :nobody_signed_up` and gets none.
  """
  def one_admin_to_sign_in_as(%{nobody_signed_up: true}), do: :ok

  def one_admin_to_sign_in_as(_context) do
    %{kb: Texttile.AccountsFixtures.user_fixture(%{username: "kb"})}
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
  """
  def await_live(session) do
    PhoenixTest.assert_has(session, "[data-phx-main].phx-connected")
  end

  @doc """
  Opens a screen of the admin area and waits for it to be live. The one
  way into a screen that carries a LiveView.
  """
  def open(session, path) do
    session |> PhoenixTest.visit(path) |> await_live()
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
    session |> PhoenixTest.visit(path) |> PhoenixTest.assert_has("body[data-ready]")
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
    |> PhoenixTest.assert_has("#tilesBlock[data-ready]")
  end

  @doc """
  Signs kb in and lands in the admin area, live.

  Every browser test starts here, so the wait for the script belongs
  here too.
  """
  def sign_in(session) do
    # The sign-in screen carries no LiveView, so there is nothing to
    # wait for until the admin area answers below.
    session
    |> PhoenixTest.visit("/login")
    |> PhoenixTest.fill_in("Username", with: "kb")
    |> PhoenixTest.fill_in("Password", with: Texttile.AccountsFixtures.valid_password())
    |> PhoenixTest.click_button("Sign in")
    |> PhoenixTest.assert_has("#crumb", text: "Entries")
    |> await_live()
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

    PhoenixTest.Playwright.evaluate(
      session,
      "t => document.querySelectorAll(\"input[name='t']\").forEach(el => el.value = t)",
      is_function: true,
      arg: stamp
    )
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
