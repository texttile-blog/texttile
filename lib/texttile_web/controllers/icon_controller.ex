defmodule TexttileWeb.IconController do
  @moduledoc """
  The icon a phone puts on its home screen. A phone takes no SVG for
  that square, so the site renders a PNG from its favicon instead of
  letting the reader end up with a blank tile.
  """
  use TexttileWeb, :controller

  alias Texttile.Images
  alias Texttile.Uploads

  def touch(conn, _params) do
    case Images.touch_icon() do
      {:ok, relative} ->
        conn
        |> put_resp_content_type("image/png")
        # the address never changes, the favicon behind it can, so the
        # icon is kept for an hour and no longer
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_file(200, Uploads.absolute(relative))

      {:error, _reason} ->
        send_resp(conn, 404, "not found")
    end
  end
end
