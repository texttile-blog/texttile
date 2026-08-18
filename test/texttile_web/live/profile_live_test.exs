defmodule TexttileWeb.ProfileLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  setup :register_and_log_in_user

  test "shows the profile with the current values", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/admin/profile")

    assert html =~ "Your profile"
    assert has_element?(view, "#crumb", "Your profile")

    assert has_element?(view, ~s(#email-form input[name="em[email]"][value="#{user.email}"]))
    assert has_element?(view, "#savedProfile")
    refute html =~ "user[username]"
  end

  test "changes the displayed name instantly, menu included", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    view
    |> form("#profile-form", %{"user" => %{"display_name" => "Klaus"}})
    |> render_change(%{"_target" => ["user", "display_name"]})

    assert has_element?(view, "#wmMe", "Klaus")
    assert has_element?(view, "#profileWho", "Klaus")
    assert Accounts.get_user!(user.id).display_name == "Klaus"
  end

  test "an empty displayed name falls back to the part before the @", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    view
    |> form("#profile-form", %{"user" => %{"display_name" => ""}})
    |> render_change(%{"_target" => ["user", "display_name"]})

    assert has_element?(view, "#wmMe", Accounts.display_name(user))
    refute render(view) =~ ~r/wmMe[^>]*>[^<]*@/
  end

  test "changes the address against the password", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    html =
      view
      |> form("#email-form", %{
        "em" => %{"email" => "new@example.org", "current_password" => valid_password()}
      })
      |> render_submit()

    assert html =~ "Your account is at new@example.org now"
    assert Accounts.get_user!(user.id).email == "new@example.org"
    assert {:ok, _} = Accounts.authenticate_user("new@example.org", valid_password())
  end

  # Whoever moves the address owns the next password link, so a stolen
  # session must not be enough to move it.
  test "refuses the address change without the current password", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    html =
      view
      |> form("#email-form", %{
        "em" => %{"email" => "thief@example.org", "current_password" => "wrong current!"}
      })
      |> render_submit()

    assert html =~ "is not your current password"
    assert Accounts.get_user!(user.id).email == user.email
  end

  test "refuses an address that is none, and one somebody else has", %{conn: conn, user: user} do
    user_fixture(%{email: "taken@example.org"})
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    html =
      view
      |> form("#email-form", %{
        "em" => %{"email" => "broken", "current_password" => valid_password()}
      })
      |> render_submit()

    assert html =~ "must be an email address"

    html =
      view
      |> form("#email-form", %{
        "em" => %{"email" => "taken@example.org", "current_password" => valid_password()}
      })
      |> render_submit()

    assert html =~ "is already in use"
    assert Accounts.get_user!(user.id).email == user.email
  end

  test "sets a new password only with the current one", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    html =
      view
      |> form("#password-form", %{
        "pw" => %{"current_password" => "wrong current!", "password" => "a brand new password"}
      })
      |> render_submit()

    assert html =~ "is not your current password"
    assert :error = Accounts.authenticate_user(user.email, "a brand new password")

    html =
      view
      |> form("#password-form", %{
        "pw" => %{"current_password" => valid_password(), "password" => "a brand new password"}
      })
      |> render_submit()

    assert html =~ "Your new password is set"
    assert {:ok, _} = Accounts.authenticate_user(user.email, "a brand new password")
  end

  test "a changed password ends every other session", %{conn: conn, user: user} do
    other_token = Accounts.create_session(user)
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

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
    {:ok, view, _html} = live(conn, ~p"/admin/profile")

    assert has_element?(view, "#sessions", "This browser")
    assert has_element?(view, "#sessions", "Another browser")
    refute has_element?(view, "#sessions", "the only one open")
  end

  test "a single session is the only one open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")
    assert has_element?(view, "#sessions", "This browser")
    assert has_element?(view, "#sessions", "the only one open")
  end

  test "offers sign out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")
    assert has_element?(view, "#sign-out", "Sign out")
  end

  test "offers sign out everywhere only while other sessions are open", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/profile")
    refute has_element?(view, "#sign-out-all")

    Accounts.create_session(user)
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/admin/profile")
    assert has_element?(view, "#sign-out-all", "Sign out everywhere")
  end
end
