defmodule TexttileWeb.E2E.LoginFlowTest do
  use TexttileWeb.E2E

  describe "the first admin" do
    # A blog nobody has signed in to yet: these tests make their own
    # first admin, so the shared one would be in the way.
    @describetag :nobody_signed_up

    test "the address in ADMIN_USERS gets a link and walks into the admin area", %{conn: conn} do
      configure_admin_emails(["kb@example.org"])

      # what the start of the server does, without restarting it
      Texttile.Accounts.Bootstrap.run()

      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> assert_has("#link-who", text: "opens the admin account of")
      |> assert_has("#link-who", text: "kb@example.org")
      |> fill_in("Your password", with: "a long password")
      |> fill_in("Repeat the password", with: "a long password")
      |> fill_in("Displayed name", with: "KB")
      |> click_button("Open the account and sign in")
      |> assert_has("#crumb", text: "Entries")
      |> assert_has("h1", text: "Entries")
      |> click_button("#wmBtn", "Texttile")
      |> assert_has("#wmMe", text: "KB")
    end

    # Nobody knows this password yet, and the name under the entries is
    # chosen here or nowhere.
    test "a typo and a missing name stay on the screen", %{conn: conn} do
      configure_admin_emails(["kb@example.org"])
      Texttile.Accounts.Bootstrap.run()

      assert_receive {:email, %Swoosh.Email{} = mail}, 2000
      [link] = Regex.run(~r"http://[^\s]+/link/[^\s]+", mail.text_body)

      conn
      |> visit(link)
      |> fill_in("Your password", with: "a long password")
      |> fill_in("Repeat the password", with: "a long passwort")
      |> fill_in("Displayed name", with: "KB")
      |> click_button("Open the account and sign in")
      |> assert_has("p", text: "does not match the password")
      # the name that was typed is still there after a refused answer
      |> assert_has("#link-display-name[value='KB']")
      |> fill_in("Your password", with: "a long password")
      |> fill_in("Repeat the password", with: "a long password")
      |> fill_in("Displayed name", with: "")
      |> click_button("Open the account and sign in")
      |> assert_has("p", text: "cannot be empty")
      |> fill_in("Your password", with: "a long password")
      |> fill_in("Repeat the password", with: "a long password")
      |> fill_in("Displayed name", with: "KB")
      |> click_button("Open the account and sign in")
      |> assert_has("#crumb", text: "Entries")
    end

    # There is no door on this screen that makes an account, so a
    # stranger who knows the address gets nowhere with it.
    test "the sign-in screen opens nothing for an address that was only invited", %{conn: conn} do
      configure_admin_emails(["kb@example.org"])
      Texttile.Accounts.Bootstrap.run()

      conn
      |> visit("/login")
      |> assert_has("#login-nobody", text: "No account here has a password yet")
      |> fill_in("Email address", with: "kb@example.org")
      |> fill_in("Password", with: "let me in please")
      |> click_button("Sign in")
      |> assert_has("#login-error", text: "do not match")
    end
  end

  describe "a forgotten password" do
    test "the link from the mail sets a new one and signs in", %{conn: conn, kb: user} do
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
      |> assert_has("#link-who", text: "belongs to the account kb@example.org")
      |> fill_in("New password", with: "a brand new password")
      |> click_button("Set the password and sign in")
      |> assert_has("#crumb", text: "Entries")

      assert {:ok, _} =
               Texttile.Accounts.authenticate_user("kb@example.org", "a brand new password")
    end

    test "an address without an account gets no mail", %{conn: conn} do
      conn
      |> visit("/forgot")
      |> fill_in("Email address", with: "nobody@example.org")
      |> click_button("Send the link")
      |> assert_has("#forgot-sent", text: "The mail is on its way")

      refute_receive {:email, _}, 500
    end
  end

  describe "sign-in" do
    test "wrong credentials leave a quiet line, right ones open the admin area", %{conn: conn} do
      conn
      |> visit("/admin")
      |> assert_has("p", text: "Admin sign-in")
      |> fill_in("Email address", with: "kb@example.org")
      |> fill_in("Password", with: "wrong password!")
      |> click_button("Sign in")
      |> assert_has("#login-error", text: "do not match")
      |> fill_in("Password", with: valid_password())
      |> click_button("Sign in")
      |> assert_has("#crumb", text: "Entries")
    end
  end

  describe "the admin area" do
    test "the wordmark menu opens with sections and presence", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("#wmBtn", "Texttile")
      |> assert_has("#navMenu", text: "New entry")
      |> assert_has("#navMenu", text: "Here now")
      |> assert_has("#navMenu", text: "No one else right now.")
      |> assert_has("#wmMe", text: "kb")
    end
  end

  describe "profile" do
    test "edits save instantly and follow into the menu", %{conn: conn} do
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
  end
end
