defmodule TexttileWeb.ThemeController do
  @moduledoc """
  The one theme stylesheet, loaded after app.css on every page: the
  stored theme.css from Settings, or the iris default while nothing is
  stored. The admin area and the public site both wear it.
  """
  use TexttileWeb, :controller

  alias Texttile.Settings

  def show(conn, _params) do
    css = Settings.theme_css()

    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, css)
  end
end
