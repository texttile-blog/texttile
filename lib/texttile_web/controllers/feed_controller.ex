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
      # Nobody keeps this answer: the password may go away in the next
      # minute, and the feed is back.
      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(404, "not found")
    end
  end

  # How long a reader may keep the feed before asking again. The word
  # is "private": only the reader that asked may keep it. A shared
  # cache in between would go on handing out the texts after a
  # password went up in front of the blog.
  @keep "private, max-age=900"

  # A whole blog is a long answer, and a reader asks for it again and
  # again. Every answer carries a tag of what it says; a reader that
  # sends the tag back gets the short "nothing new" instead of the
  # texts.
  defp send_feed(conn, body) do
    tag = etag(body)
    conn = conn |> put_resp_header("etag", tag) |> put_resp_header("cache-control", @keep)

    if known?(conn, tag) do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("application/rss+xml")
      |> send_resp(200, body)
    end
  end

  defp etag(body) do
    hash = :crypto.hash(:md5, body) |> Base.encode16(case: :lower)
    ~s("#{hash}")
  end

  # What the reader already has. "*" means anything at all, and a
  # proxy on the way may have marked the tag as weak; the comparison
  # ignores that mark, the way HTTP asks for on this header.
  defp known?(conn, tag) do
    sent =
      conn
      |> get_req_header("if-none-match")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&(&1 |> String.trim() |> String.replace_prefix("W/", "")))

    "*" in sent or tag in sent
  end
end
