defmodule TexttileWeb.SiteUnpublishedTest do
  @moduledoc """
  An entry wears its address before it is live. The site answers there
  for whoever is signed in and nowhere else, so the editor's way out
  leads into the real reader's page instead of a second design of it.
  """
  use TexttileWeb.ConnCase, async: true

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  defp dated_draft(attrs) do
    attrs = Map.new(attrs)
    user = user_fixture()
    article = draft_post(Map.put(attrs, :user, user))
    {:ok, article} = Articles.set_publish_date(article, user, Map.fetch!(attrs, :publish_date))
    article
  end

  describe "a draft at its address" do
    test "answers a signed-in admin", %{conn: conn} do
      dated_draft(title: "The harbour", slug: "harbour", publish_date: ~D[2026-08-08])

      html =
        conn
        |> log_in_user(user_fixture())
        |> get(~p"/2026/08/08/harbour")
        |> html_response(200)

      assert html =~ "The harbour"
      assert html =~ ~s(id="not-live")
      assert html =~ "Draft."
    end

    test "is a 404 for a reader", %{conn: conn} do
      dated_draft(title: "The harbour", slug: "harbour", publish_date: ~D[2026-08-08])

      conn = get(conn, ~p"/2026/08/08/harbour")
      assert html_response(conn, 404) =~ "Not found"
    end

    test "takes no comments while it is not live", %{conn: conn} do
      article = dated_draft(title: "The harbour", slug: "harbour", publish_date: ~D[2026-08-08])
      assert article.allow_comments

      html =
        conn
        |> log_in_user(user_fixture())
        |> get(~p"/2026/08/08/harbour")
        |> html_response(200)

      refute html =~ ~s(id="comment-form")
    end
  end

  describe "a scheduled entry at its address" do
    test "answers a signed-in admin and says which state it is in", %{conn: conn} do
      article = scheduled_post(title: "Next week", slug: "next-week")
      path = Articles.public_path(article)

      html = conn |> log_in_user(user_fixture()) |> get(path) |> html_response(200)

      assert html =~ "Next week"
      assert html =~ "Scheduled."
    end
  end

  describe "a page that is not live" do
    test "answers a signed-in admin at its short address", %{conn: conn} do
      draft_post(title: "About us", slug: "about-us", type: "page")

      html = conn |> log_in_user(user_fixture()) |> get(~p"/about-us") |> html_response(200)
      assert html =~ "About us"
      assert html =~ ~s(id="not-live")
    end

    test "is a 404 for a reader", %{conn: conn} do
      draft_post(title: "About us", slug: "about-us", type: "page")

      assert conn |> get(~p"/about-us") |> html_response(404)
    end
  end

  describe "a live entry" do
    test "carries no strip", %{conn: conn} do
      article = published_post(title: "The harbour", slug: "harbour")

      html =
        conn
        |> log_in_user(user_fixture())
        |> get(Articles.public_path(article))
        |> html_response(200)

      refute html =~ ~s(id="not-live")
    end
  end
end
