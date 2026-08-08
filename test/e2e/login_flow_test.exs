defmodule TexttileWeb.E2E.LoginFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures
  import TexttileWeb.E2E, only: [sign_in: 1, open: 2]

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  setup do
    # The browser talks to the same node, so the configured usernames are
    # the ones this test sets. They go back after it.
    Texttile.DataCase.restore_admin_users_afterwards()
    :ok
  end

  describe "the first sign-in" do
    test "a configured name walks through the password screen into the admin area", %{conn: conn} do
      configure_admins(["kb"])

      conn
      |> visit("/admin")
      |> assert_has("p", text: "Admin sign-in")
      |> fill_in("Username", with: "kb")
      |> click_button("Sign in")
      |> assert_has("h2", text: "Choose a password")
      |> fill_in("Password", with: "a long password")
      |> fill_in("Repeat the password", with: "a long password")
      |> fill_in("Email address", with: "kb@example.org")
      |> fill_in("Displayed name", with: "KB")
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
      |> fill_in("Email address", with: "kb@example.org")
      |> click_button("Create the account and sign in")
      |> assert_has("p", text: "at least 12 characters")
      |> assert_has("p", text: "does not match")
    end
  end

  describe "a forgotten password" do
    test "the link from the mail sets a new one and signs in", %{conn: conn} do
      user = user_fixture(%{username: "kb"})

      # Mails from the server processes land in this test process.
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

      conn
      |> visit("/login")
      |> click_link("Forgot your password?")
      |> fill_in("Email address", with: user.email)
      |> click_button("Send the link")
      |> assert_has("#forgot-sent", text: "The mail is on its way")

      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> assert_has("#link-who", text: "belongs to the account kb")
      |> fill_in("New password", with: "a brand new password")
      |> click_button("Set the password and sign in")
      |> assert_has("#crumb", text: "Texts")

      assert {:ok, _} = Texttile.Accounts.authenticate_user("kb", "a brand new password")
    end

    test "a name the configuration dropped gets no mail", %{conn: conn} do
      user = user_fixture(%{username: "kb"})
      configure_admins([])

      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

      conn
      |> visit("/forgot")
      |> fill_in("Email address", with: user.email)
      |> click_button("Send the link")
      |> assert_has("#forgot-sent", text: "The mail is on its way")

      refute_receive {:email, _}, 500
    end
  end

  describe "sign-in" do
    test "wrong credentials leave a quiet line, right ones open the admin area", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn
      |> visit("/admin")
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

  describe "the admin area" do
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
      # the menu opens in the browser: wait for it, or the next click
      # races the script on a slow machine
      |> assert_has("#navMenu", text: "Your profile")
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
      |> open("/admin/profile")
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
      |> open("/admin/profile")
      |> click_link("#sign-out", "Sign out")
      |> assert_has("p", text: "Admin sign-in")
    end
  end
end
