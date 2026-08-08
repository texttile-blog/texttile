defmodule TexttileWeb.StatsBeaconTest do
  use TexttileWeb.ConnCase

  import Texttile.ArticlesFixtures

  alias Texttile.Stats

  @agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
           "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"

  setup do
    Texttile.RateLimiter.reset(Texttile.Stats.Limiter)
    :ok
  end

  defp beacon(conn, body, headers \\ []) do
    conn = put_req_header(conn, "user-agent", @agent)

    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/count", Jason.encode!(body))
  end

  test "a browser on a reader page is counted, and hears nothing back", %{conn: conn} do
    conn = beacon(conn, %{p: "/blog"})

    assert conn.status == 204
    assert conn.resp_body == ""
    assert Stats.summary(30).views == 1
  end

  test "the answer carries no cookie: nothing is stored in the browser", %{conn: conn} do
    conn = beacon(conn, %{p: "/blog"})

    assert conn.resp_cookies == %{}
  end

  test "the entry travels with the view", %{conn: conn} do
    article = published_post(%{title: "Concrete flowers"})

    beacon(conn, %{p: "/2026/08/08/concrete-flowers", id: article.id})

    assert [%{article: %{id: id}, views: 1}] = Stats.top_articles(10)
    assert id == article.id
  end

  test "the referrer travels with the view", %{conn: conn} do
    beacon(conn, %{p: "/blog", r: "https://lobste.rs/s/abc"})

    assert [%{host: "lobste.rs"}] = Stats.referrers(30)
  end

  test "a bot hears the same nothing and is not counted", %{conn: conn} do
    conn =
      conn
      |> put_req_header("user-agent", "Mozilla/5.0 (compatible; Googlebot/2.1)")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/count", Jason.encode!(%{p: "/blog"}))

    assert conn.status == 204
    assert Stats.summary(30).views == 0
  end

  test "a page the browser fetched ahead is not counted", %{conn: conn} do
    beacon(conn, %{p: "/blog"}, [{"sec-purpose", "prefetch;anonymous-client-ip"}])

    assert Stats.summary(30).views == 0
  end

  test "junk instead of an address is answered, not counted", %{conn: conn} do
    for body <- [%{}, %{p: 42}, %{p: ["/blog"]}, %{p: "javascript:alert(1)"}] do
      assert beacon(conn, body).status == 204
    end

    assert Stats.summary(30).views == 0
  end

  test "junk instead of an entry counts as a plain address", %{conn: conn} do
    assert beacon(conn, %{p: "/blog", id: "seven"}).status == 204

    assert Stats.summary(30).views == 1
    assert Stats.top_articles(10) == []
  end

  test "one caller cannot flood the numbers", %{conn: conn} do
    for n <- 1..80, do: beacon(conn, %{p: "/p#{n}"})

    assert Stats.summary(30).views == 60
  end
end
