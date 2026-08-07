defmodule TexttileWeb.FeedController do
  @moduledoc """
  The feed, for readers who follow the blog from their own reader.

  It stands outside the password gate on purpose. A gate would send a
  feed reader to a login screen and it would show that as the newest
  text. A guarded blog has no feed at all, and says so with 404.
  """
  use TexttileWeb, :controller

  alias Texttile.Feed

  def show(conn, _params) do
    if Feed.public?() do
      send_feed(conn, Feed.rss(TexttileWeb.Endpoint.url()))
    else
      send_resp(conn, 404, "not found")
    end
  end

  # A whole blog is a long answer, and a reader asks for it again and
  # again. Every answer carries a tag of what it says; a reader that
  # sends the tag back gets the short "nothing new" instead of the
  # texts.
  defp send_feed(conn, body) do
    tag = etag(body)

    if tag in requested_tags(conn) do
      conn |> put_resp_header("etag", tag) |> send_resp(304, "")
    else
      conn
      |> put_resp_header("etag", tag)
      |> put_resp_content_type("application/rss+xml")
      |> send_resp(200, body)
    end
  end

  defp etag(body) do
    hash = :crypto.hash(:md5, body) |> Base.encode16(case: :lower)
    ~s("#{hash}")
  end

  defp requested_tags(conn) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
  end
end
