defmodule TexttileWeb.ThemeController do
  @moduledoc """
  The one theme stylesheet, loaded after app.css on every page: the
  tokens the stored theme changes, and nothing while none is stored
  (app.css carries the iris default). The admin area and the public
  site both wear it.
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
