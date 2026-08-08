defmodule TexttileWeb.E2E.LanguageFlowTest do
  @moduledoc """
  The language, in a real browser.

  Most of the words come from the server, and the LiveView tests read
  those. These do not: the gallery writes its own text in the browser,
  out of the object the layout hands it. Nothing but a browser runs
  that, so nothing but a browser test can say whether a German site
  speaks German where the script does the talking.
  """

  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures
  import TexttileWeb.E2E, only: [sign_in: 1, open_editor: 2]

  alias Texttile.Articles
  alias Texttile.Settings

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  setup do
    Texttile.DataCase.restore_admin_users_afterwards()

    Texttile.Articles.Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Texttile.Articles.Lock.supervisor(), pid)
    end)

    %{kb: user_fixture(%{username: "kb"})}
  end

  defp draft!(user) do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, %{title: "Türen", body: "Hölzerne."})
    article
  end

  test "the gallery says its own words in the language of the site", %{conn: conn, kb: kb} do
    article = draft!(kb)

    # Signed in first, then the language: the sign-in screen speaks it
    # too, and the helper knows the English one.
    session = sign_in(conn)
    {:ok, _} = Settings.put(:language, "de")

    session
    |> open_editor(article.id)
    # written by the server, into the tiles block
    |> assert_has("#tileCount", text: "0 Kacheln")
    # written by the hook, out of data-words: without the object, or
    # with the object read once and never again, this stays English
    |> assert_has("#tileAdd", text: "+ Hinzufügen")
  end

  test "an English site keeps the English the hooks are written in", %{conn: conn, kb: kb} do
    article = draft!(kb)
    {:ok, _} = Settings.put(:language, "en")

    conn
    |> sign_in()
    |> open_editor(article.id)
    |> assert_has("#tileCount", text: "0 tiles")
    |> assert_has("#tileAdd", text: "+ Add")
  end

  test "the language a reader meets follows the setting", %{conn: conn, kb: kb} do
    article = draft!(kb)
    {:ok, _} = Articles.publish(article, kb)
    {:ok, _} = Settings.put(:language, "de")

    # The reader pages are no LiveView, so there is nothing live to
    # wait for: the words stand in the first render.
    conn
    |> PhoenixTest.visit("/blog")
    |> assert_has("h1", text: "Blogeinträge")
  end
end
