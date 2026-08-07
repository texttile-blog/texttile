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
      conn
      |> put_resp_content_type("application/rss+xml")
      |> send_resp(200, Feed.rss(TexttileWeb.Endpoint.url()))
    else
      send_resp(conn, 404, "not found")
    end
  end
end
