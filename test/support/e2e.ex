defmodule TexttileWeb.E2E do
  @moduledoc """
  Shared plumbing for the browser tests.
  """

  @doc """
  Closes the test's browser context the moment the test ends, before
  the next one starts.

  The Playwright case closes contexts in a spawned process, so a page
  can outlive its test. Its LiveViews then reconnect mid-run under a
  sandbox owner that is already dead, and SQLite's single writer turns
  that race into stalls in whatever test runs next. Registered after
  the case's own setup, this runs first on exit and closes the context
  synchronously.
  """
  def close_browser_context_afterwards(%{conn: conn}) do
    # The browser tests keep their own sandbox, so they never pass
    # through Texttile.DataCase. They open editors like nobody else,
    # and their locks outlive them the same way, so they start from
    # none too.
    Texttile.DataCase.forget_open_editors()

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
  Waits until the page in the browser is a live one.

  The server answers a LiveView with a dead render first, and the
  script picks it up a moment later. Playwright acts as soon as an
  element stands in the DOM, so a click can land in that moment: the
  button is there, nothing listens, and no error says so. The test
  then waits for a result that can never come.

  A developer machine hides this, because the script is up before the
  first click. A loaded CI runner does not. Every browser test that
  clicks, types or presses a key waits here first.
  """
  def await_live(session) do
    PhoenixTest.assert_has(session, "[data-phx-main].phx-connected")
  end

  @doc """
  Opens a page of the admin area and waits for it to be live.
  """
  def open(session, path) do
    session |> PhoenixTest.visit(path) |> await_live()
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
    session
    |> PhoenixTest.visit("/login")
    |> PhoenixTest.fill_in("Username", with: "kb")
    |> PhoenixTest.fill_in("Password", with: Texttile.AccountsFixtures.valid_password())
    |> PhoenixTest.click_button("Sign in")
    |> PhoenixTest.assert_has("#crumb", text: "Entries")
    |> await_live()
  end
end
