defmodule TexttileWeb.SiteCountedTest do
  @moduledoc """
  Which reader pages report themselves to the view counter, and which
  never do.
  """
  use TexttileWeb.ConnCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Settings

  defp counted?(html), do: html =~ ~s(data-count="1")

  describe "the pages a reader reads" do
    test "the list reports itself", %{conn: conn} do
      assert conn |> get(~p"/blog") |> html_response(200) |> counted?()
    end

    test "a tag archive reports itself", %{conn: conn} do
      published_post(title: "Slow trains", tags: "trains")

      assert conn |> get(~p"/tags/trains") |> html_response(200) |> counted?()
    end

    test "an entry reports itself and names its own id", %{conn: conn} do
      article = published_post(title: "Concrete flowers")

      html = conn |> get(Texttile.Articles.public_path(article)) |> html_response(200)

      assert counted?(html)
      assert html =~ ~s(data-count-entry="#{article.id}")
    end

    test "a page reports itself and names its own id", %{conn: conn} do
      page = published_page(title: "About the blog")

      html = conn |> get(Texttile.Articles.public_path(page)) |> html_response(200)

      assert counted?(html)
      assert html =~ ~s(data-count-entry="#{page.id}")
    end
  end

  describe "the pages that are nobody's reading" do
    test "the gate reports nothing", %{conn: conn} do
      Settings.put(:site_visibility, "protected")
      Settings.put(:site_password, "open sesame")

      refute conn |> get(~p"/unlock") |> html_response(200) |> counted?()
    end

    test "an address that holds nothing reports nothing", %{conn: conn} do
      refute conn |> get(~p"/nothing-lives-here") |> html_response(404) |> counted?()
    end

    test "an admin reading their own blog is not a reader", %{conn: conn} do
      article = published_post(title: "Concrete flowers")
      conn = log_in_user(conn, user_fixture())

      html = conn |> get(Texttile.Articles.public_path(article)) |> html_response(200)

      refute counted?(html)
      refute html =~ "data-count-entry"
    end

    test "a preview reports nothing: it is the writer looking", %{conn: conn} do
      draft = draft_post(title: "Fog over the harbor")
      conn = log_in_user(conn, user_fixture())

      refute conn |> get(~p"/preview/#{draft.id}") |> html_response(200) |> counted?()
    end
  end
end
