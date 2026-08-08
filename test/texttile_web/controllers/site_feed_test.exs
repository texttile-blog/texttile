defmodule TexttileWeb.FeedControllerTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Settings

  describe "an open blog" do
    test "serves the feed as RSS", %{conn: conn} do
      published_post(title: "Harbor mornings")

      conn = get(conn, ~p"/feed.xml")

      assert response(conn, 200) =~ "Harbor mornings"
      assert response_content_type(conn, :xml) =~ "application/rss+xml"
    end

    test "sends nothing a second time while nothing changed", %{conn: conn} do
      published_post(title: "Harbor mornings")

      first = get(conn, ~p"/feed.xml")
      [tag] = get_resp_header(first, "etag")

      again = build_conn() |> put_req_header("if-none-match", tag) |> get(~p"/feed.xml")

      assert again.status == 304
      assert response(again, 304) == ""
    end

    test "answers a tag that a proxy weakened, and a reader that asks for any", %{conn: conn} do
      published_post(title: "Harbor mornings")

      [tag] = conn |> get(~p"/feed.xml") |> get_resp_header("etag")
      weak = "W/" <> tag

      for sent <- [weak, "*", ~s("something-else"), tag] do
        answer = build_conn() |> put_req_header("if-none-match", sent) |> get(~p"/feed.xml")

        expected = if sent == ~s("something-else"), do: 200, else: 304
        assert answer.status == expected, "#{sent} answered #{answer.status}"
      end
    end

    test "lets a reader keep the feed for a while", %{conn: conn} do
      conn = get(conn, ~p"/feed.xml")

      assert [cache] = get_resp_header(conn, "cache-control")
      assert cache =~ "max-age="
    end

    test "sends the feed again once a text has changed", %{conn: conn} do
      published_post(title: "Harbor mornings")

      first = get(conn, ~p"/feed.xml")
      [tag] = get_resp_header(first, "etag")

      published_post(title: "Desert nights")

      again = build_conn() |> put_req_header("if-none-match", tag) |> get(~p"/feed.xml")

      assert response(again, 200) =~ "Desert nights"
    end
  end

  describe "a blog behind a password" do
    setup do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")
      :ok
    end

    test "has no feed, and does not send the reader to the gate", %{conn: conn} do
      published_post(title: "Behind the wall")

      conn = get(conn, ~p"/feed.xml")

      assert conn.status == 404
      refute response(conn, 404) =~ "Behind the wall"
    end

    test "keeps the feed from a signed-in admin too", %{conn: conn} do
      conn =
        conn
        |> log_in_user(Texttile.AccountsFixtures.user_fixture())
        |> get(~p"/feed.xml")

      assert conn.status == 404
    end
  end

  describe "the way to the feed" do
    test "stands in the head and in the foot while the blog is open", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(rel="alternate")
      assert html =~ ~s(type="application/rss+xml")
      assert html =~ ~s(href="/feed.xml")
    end

    test "is gone while a password guards the blog", %{conn: conn} do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      html =
        conn
        |> init_test_session(site_unlocked: true)
        |> get(~p"/")
        |> html_response(200)

      refute html =~ "application/rss+xml"
      refute html =~ "/feed.xml"
    end
  end
end
