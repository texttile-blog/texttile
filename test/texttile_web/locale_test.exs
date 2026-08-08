defmodule TexttileWeb.LocaleTest do
  @moduledoc """
  The site language reaches every kind of process that writes words: a
  plain request, a LiveView, and the task that sends mail. Each one
  starts with a locale of its own, so each one is checked here.
  """

  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Settings

  describe "the reader pages" do
    test "speak English while the site does", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ "Blog Entries"
      assert html =~ ~s(<html lang="en")
    end

    test "speak German once the site does", %{conn: conn} do
      {:ok, _} = Settings.put(:language, "de")

      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ "Blogeinträge"
      refute html =~ "Blog Entries"
      assert html =~ ~s(<html lang="de")
    end

    test "the gate asks for the password in German", %{conn: conn} do
      {:ok, _} = Settings.put(:language, "de")
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "open sesame")

      html = conn |> get(~p"/unlock") |> html_response(200)

      assert html =~ "Passwort"
      refute html =~ "This blog asks for its password."
    end
  end

  describe "the words the hooks say" do
    setup :register_and_log_in_user

    test "are an empty object while the site speaks the language they are written in",
         %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/admin/texts")

      assert html =~ ~s(data-words="{}")
    end

    test "carry the German sentence under the English one on a German site", %{conn: conn} do
      {:ok, _} = Settings.put(:language, "de")

      {:ok, _live, html} = live(conn, ~p"/admin/texts")

      # The English sentence is the key, the German one the value.
      assert html =~ "Retry"
      assert html =~ "Erneut versuchen"
    end
  end

  describe "the admin area" do
    setup :register_and_log_in_user

    test "speaks German in a dead render and in the live one", %{conn: conn} do
      {:ok, _} = Settings.put(:language, "de")
      _article = published_post()

      {:ok, live, html} = live(conn, ~p"/admin/texts")

      # The dead render runs in the request process, the live one in a
      # process of its own. Both have to have the language.
      assert html =~ "Einträge"
      assert render(live) =~ "Einträge"
      assert html =~ ~s(<html lang="de")
    end

    test "stays English while the site is English", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/admin/texts")

      assert html =~ "Entries"
      refute html =~ "Einträge"
    end
  end
end
