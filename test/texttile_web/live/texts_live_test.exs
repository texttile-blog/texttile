defmodule TexttileWeb.TextsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "shows the desk shell with the wordmark menu", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Texts"
    assert has_element?(view, "#topbar")
    assert has_element?(view, "#wmBtn")
    assert has_element?(view, "#crumb", "Texts")

    # the menu: the sections with their digits, profile, sign out
    assert has_element?(view, "#navMenu", "New text")
    assert has_element?(view, "#navMenu", "Comments")
    assert has_element?(view, "#navMenu", "Newsletter")
    assert has_element?(view, "#navMenu", "Stats")
    assert has_element?(view, "#navMenu", "Settings")
    assert has_element?(view, "#navMenu", "View site")
    assert has_element?(view, "#navMenu a", "Your profile")
    assert has_element?(view, "#navMenu a", "Sign out")

    # presence: alone at the desk
    assert has_element?(view, "#liveBlock", "No one else right now.")

    # the five theme swatches
    for theme <- ~w(paper iris elixir signal darkroom) do
      assert has_element?(view, ~s(#themeRow [data-t="#{theme}"]))
    end
  end

  test "names the signed-in admin in the menu", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#wmMe", user.username)
  end

  test "the New text button waits, disabled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "button[disabled]", "New text")
  end
end
