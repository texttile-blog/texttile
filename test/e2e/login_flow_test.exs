defmodule TexttileWeb.E2E.LoginFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  @moduletag :e2e

  setup do
    # The browser talks to the same node, so the configured usernames are
    # the ones this test sets. They go back after it.
    Texttile.DataCase.restore_admin_users_afterwards()
    :ok
  end

  describe "the first sign-in" do
    test "a configured name walks through the password screen onto the desk", %{conn: conn} do
      configure_admins(["kb"])

      conn
      |> visit("/")
      |> assert_has("p", text: "Admin sign-in")
      |> fill_in("Username", with: "kb")
      |> click_button("Sign in")
      |> assert_has("h2", text: "Choose a password")
      |> fill_in("Password", with: "a long password")
      |> fill_in("Repeat the password", with: "a long password")
      |> click_button("Create the account and sign in")
      |> assert_has("#crumb", text: "Texts")
      |> assert_has("h1", text: "Texts")
    end

    test "a name nobody configured gets the answer of a wrong password", %{conn: conn} do
      configure_admins(["kb"])

      conn
      |> visit("/login")
      |> fill_in("Username", with: "julia")
      |> fill_in("Password", with: "let me in please")
      |> click_button("Sign in")
      |> assert_has("#login-error", text: "do not match")
    end

    test "bad input stays on the password screen and says why", %{conn: conn} do
      configure_admins(["kb"])

      conn
      |> visit("/login")
      |> fill_in("Username", with: "kb")
      |> click_button("Sign in")
      |> fill_in("Password", with: "short")
      |> fill_in("Repeat the password", with: "shorter")
      |> click_button("Create the account and sign in")
      |> assert_has("p", text: "at least 12 characters")
      |> assert_has("p", text: "does not match")
    end
  end

  describe "sign-in" do
    test "wrong credentials leave a quiet line, right ones open the desk", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn
      |> visit("/")
      |> assert_has("p", text: "Admin sign-in")
      |> fill_in("Username", with: "kb")
      |> fill_in("Password", with: "wrong password!")
      |> click_button("Sign in")
      |> assert_has("#login-error", text: "do not match")
      |> fill_in("Password", with: valid_password())
      |> click_button("Sign in")
      |> assert_has("#crumb", text: "Texts")
    end
  end

  describe "the desk" do
    test "the wordmark menu opens with sections and presence", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn
      |> sign_in()
      |> click_button("#wmBtn", "Texttile")
      |> assert_has("#navMenu", text: "New text")
      |> assert_has("#navMenu", text: "Here now")
      |> assert_has("#navMenu", text: "No one else right now.")
      |> assert_has("#wmMe", text: "kb")
    end
  end

  describe "profile" do
    test "edits save instantly and follow into the menu", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn
      |> sign_in()
      |> click_button("#wmBtn", "Texttile")
      |> click_link("Your profile")
      |> assert_has("#crumb", text: "Your profile")
      |> assert_has("#sessions", text: "This browser")
      |> assert_has("#sessions", text: "the only one open")
      |> fill_in("Displayed name", with: "Klaus")
      |> assert_has("#profileWho", text: "Klaus")
      |> click_button("#wmBtn", "Texttile")
      |> assert_has("#wmMe", text: "Klaus")
    end

    test "the password changes only with the current one", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn
      |> sign_in()
      |> visit("/profile")
      |> fill_in("Current password", with: "wrong current!")
      |> fill_in("New password", with: "a brand new password")
      |> click_button("Set")
      |> assert_has("p", text: "is not your current password")
      |> fill_in("Current password", with: valid_password())
      |> fill_in("New password", with: "a brand new password")
      |> click_button("Set")
      |> assert_has("#pwMeState", text: "Your new password is set")
    end

    test "sign out returns to the sign-in screen", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn
      |> sign_in()
      |> visit("/profile")
      |> click_link("#sign-out", "Sign out")
      |> assert_has("p", text: "Admin sign-in")
    end
  end

  defp sign_in(conn) do
    conn
    |> visit("/login")
    |> fill_in("Username", with: "kb")
    |> fill_in("Password", with: valid_password())
    |> click_button("Sign in")
    |> assert_has("#crumb", text: "Texts")
  end
end
