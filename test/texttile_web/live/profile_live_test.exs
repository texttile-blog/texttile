defmodule TexttileWeb.ProfileLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  setup :register_and_log_in_user

  test "shows the profile with the current values", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/edit/profile")

    assert html =~ "Your profile"
    assert has_element?(view, "#crumb", "Your profile")

    assert has_element?(
             view,
             ~s(#profile-form input[name="user[username]"][value="#{user.username}"])
           )

    assert has_element?(view, ~s(#profile-form input[name="user[email]"][value="#{user.email}"]))
    assert has_element?(view, "#savedProfile")
  end

  test "changes the displayed name instantly, menu included", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    view
    |> form("#profile-form", %{"user" => %{"display_name" => "Klaus"}})
    |> render_change(%{"_target" => ["user", "display_name"]})

    assert has_element?(view, "#wmMe", "Klaus")
    assert has_element?(view, "#profileWho", "Klaus")
    assert Accounts.get_user!(user.id).display_name == "Klaus"
  end

  test "an empty displayed name falls back to the username", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    view
    |> form("#profile-form", %{"user" => %{"display_name" => ""}})
    |> render_change(%{"_target" => ["user", "display_name"]})

    assert has_element?(view, "#wmMe", user.username)
  end

  test "changes the username to another configured one", %{conn: conn, user: user} do
    configure_admins([user.username, "brandnew"])
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    view
    |> form("#profile-form", %{"user" => %{"username" => "brandnew"}})
    |> render_change(%{"_target" => ["user", "username"]})

    assert Accounts.get_user!(user.id).username == "brandnew"
  end

  test "refuses a username the server does not allow", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    html =
      view
      |> form("#profile-form", %{"user" => %{"username" => "stranger"}})
      |> render_change(%{"_target" => ["user", "username"]})

    assert html =~ "is not a username this server allows"
    assert Accounts.get_user!(user.id).username == user.username
  end

  test "refuses a taken username and says so", %{conn: conn, user: user} do
    user_fixture(%{username: "taken"})
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    html =
      view
      |> form("#profile-form", %{"user" => %{"username" => "taken"}})
      |> render_change(%{"_target" => ["user", "username"]})

    assert html =~ "is already taken"
    assert Accounts.get_user!(user.id).username == user.username
  end

  test "a later successful save never leaves a refused value looking saved", %{
    conn: conn,
    user: user
  } do
    user_fixture(%{username: "taken"})
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    view
    |> form("#profile-form", %{"user" => %{"username" => "taken"}})
    |> render_change(%{"_target" => ["user", "username"]})

    html =
      view
      |> form("#profile-form", %{"user" => %{"display_name" => "Klaus"}})
      |> render_change(%{"_target" => ["user", "display_name"]})

    # the username field shows what is actually saved again, not the
    # refused value with its error line gone
    refute html =~ "is already taken"

    assert has_element?(
             view,
             ~s(#profile-form input[name="user[username]"][value="#{user.username}"])
           )
  end

  test "changes the email and refuses an invalid one", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    view
    |> form("#profile-form", %{"user" => %{"email" => "new@example.org"}})
    |> render_change(%{"_target" => ["user", "email"]})

    assert Accounts.get_user!(user.id).email == "new@example.org"

    html =
      view
      |> form("#profile-form", %{"user" => %{"email" => "broken"}})
      |> render_change(%{"_target" => ["user", "email"]})

    assert html =~ "must be an email address"
  end

  test "sets a new password only with the current one", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    html =
      view
      |> form("#password-form", %{
        "pw" => %{"current_password" => "wrong current!", "password" => "a brand new password"}
      })
      |> render_submit()

    assert html =~ "is not your current password"
    assert :error = Accounts.authenticate_user(user.username, "a brand new password")

    html =
      view
      |> form("#password-form", %{
        "pw" => %{"current_password" => valid_password(), "password" => "a brand new password"}
      })
      |> render_submit()

    assert html =~ "Your new password is set"
    assert {:ok, _} = Accounts.authenticate_user(user.username, "a brand new password")
  end

  test "a changed password ends every other session", %{conn: conn, user: user} do
    other_token = Accounts.create_session(user)
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    html =
      view
      |> form("#password-form", %{
        "pw" => %{"current_password" => valid_password(), "password" => "a brand new password"}
      })
      |> render_submit()

    assert html =~ "Every other session is signed out"
    assert Accounts.get_user_by_session_token(other_token) == nil
    assert [_only_this_browser] = Accounts.list_sessions(user)
    assert has_element?(view, "#sessions", "the only one open")
  end

  test "lists the open sessions with this browser first", %{conn: conn, user: user} do
    Accounts.create_session(user)
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/edit/profile")

    assert has_element?(view, "#sessions", "This browser")
    assert has_element?(view, "#sessions", "Another browser")
    refute has_element?(view, "#sessions", "the only one open")
  end

  test "a single session is the only one open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")
    assert has_element?(view, "#sessions", "This browser")
    assert has_element?(view, "#sessions", "the only one open")
  end

  test "offers sign out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")
    assert has_element?(view, "#sign-out", "Sign out")
  end

  test "offers sign out everywhere only while other sessions are open", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/edit/profile")
    refute has_element?(view, "#sign-out-all")

    Accounts.create_session(user)
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/edit/profile")
    assert has_element?(view, "#sign-out-all", "Sign out everywhere")
  end
end
