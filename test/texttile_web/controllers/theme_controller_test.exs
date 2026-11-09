defmodule TexttileWeb.ThemeControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Repo
  alias Texttile.Settings
  alias Texttile.Settings.Setting

  test "an untouched install serves nothing over the bundled default", %{conn: conn} do
    conn = get(conn, ~p"/theme.css")

    assert response_content_type(conn, :css) =~ "text/css"
    assert response(conn, 200) == ""
  end

  # Staging stored a whole copy of an older default, field lines and
  # all, and kept its fields flat after the default had moved on.
  test "a theme stored before the contract keeps its colours and loses the rest",
       %{conn: conn} do
    Repo.insert!(%Setting{
      key: "theme_css",
      value: ":root { --tt-accent: hotpink; --fld-bg: transparent; --fld-r: 0px; }"
    })

    css = response(get(conn, ~p"/theme.css"), 200)

    assert css =~ "--tt-accent: hotpink;"
    refute css =~ "--fld-"
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
