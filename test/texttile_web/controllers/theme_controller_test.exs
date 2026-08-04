defmodule TexttileWeb.ThemeControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Settings

  test "an untouched install wears the iris theme", %{conn: conn} do
    conn = get(conn, ~p"/theme.css")

    assert response_content_type(conn, :css) =~ "text/css"
    assert response(conn, 200) =~ "--tt-accent"
  end

  test "a stored theme replaces the default the moment it exists", %{conn: conn} do
    {:ok, _} = Settings.put(:theme_css, ":root { --tt-accent: hotpink; }")

    assert response(get(conn, ~p"/theme.css"), 200) =~ "hotpink"
  end

  test "the answer is told not to be cached, so an edit shows on the next load", %{conn: conn} do
    conn = get(conn, ~p"/theme.css")

    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "no-cache"
  end
end
