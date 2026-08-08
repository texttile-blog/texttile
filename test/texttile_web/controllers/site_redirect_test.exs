defmodule TexttileWeb.SiteRedirectTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  describe "an address an entry used to live at" do
    test "sends the reader on, permanently", %{conn: conn} do
      article = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, _} = Articles.update_settings(article, %{slug: "the-harbour"})

      conn = get(conn, ~p"/2026/08/08/harbour")
      assert redirected_to(conn, 301) == "/2026/08/08/the-harbour"
    end

    test "carries a page to its new slug", %{conn: conn} do
      page = published_page(slug: "about-us")
      {:ok, _} = Articles.update_settings(page, %{slug: "about"})

      conn = get(conn, ~p"/about-us")
      assert redirected_to(conn, 301) == "/about"
    end

    test "is a 404 once it is taken off", %{conn: conn} do
      article = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, article} = Articles.update_settings(article, %{slug: "quay"})
      [old] = Articles.redirects(article)
      :ok = Articles.delete_redirect(article, old.id)

      assert conn |> get(~p"/2026/08/08/harbour") |> html_response(404)
    end
  end

  describe "an address nobody ever used" do
    test "is a 404", %{conn: conn} do
      assert conn |> get(~p"/2026/08/08/nothing-here") |> html_response(404)
    end
  end
end
