defmodule TexttileWeb.E2E.BackupFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Backup
  alias Texttile.Settings

  # The word is shown once, in a box of its own, and nowhere else. It
  # is read off the live page, because that is where it stands: the
  # first render of this screen carries no token at all.
  defp token_on_screen(session) do
    {:ok, text} =
      PlaywrightEx.Frame.text_content(session.frame_id,
        selector: "#backupToken",
        timeout: 5_000
      )

    String.trim(text)
  end

  defp fetch(path, token) do
    Req.get(TexttileWeb.Endpoint.url() <> path,
      headers: [{"authorization", "Bearer " <> token}],
      retry: false
    )
  end

  describe "the backup settings" do
    test "a fresh installation offers backups but serves none", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> assert_has("#backupSection", text: "Backup")
      |> assert_has("#backupLastAccess", text: "Nothing has been fetched yet")

      refute Backup.enabled?()
      refute Backup.token?()
    end

    test "the owner switches it on, makes a token, and a client fetches with it", %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> open("/admin/settings")
        |> check("Serve a backup client", exact: false)
        |> assert_has("#savedSettings", text: "Last saved · just now")
        |> click_button("#makeBackupToken", "Create a token")
        |> assert_has("#backupToken")

      assert Backup.enabled?()

      token = token_on_screen(session)
      assert byte_size(token) > 20

      {:ok, manifest} = fetch("/backup/manifest", token)
      assert manifest.status == 200
      assert manifest.body["texttile_version"] == Texttile.version()

      {:ok, database} = fetch("/backup/db", token)
      assert database.status == 200
      assert binary_part(database.body, 0, 15) == "SQLite format 3"

      # And the screen then says the backups run.
      session
      |> open("/admin/settings")
      |> assert_has("#backupLastAccess", text: "127.0.0.1")
      # The word itself is gone from the screen: it is kept as a hash.
      |> refute_has("#backupToken")
      |> assert_has("#backupTokenState", text: "A token is in service")
    end

    test "a new token takes the old one out of service, once it is confirmed", %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> open("/admin/settings")
        |> check("Serve a backup client", exact: false)
        |> click_button("#makeBackupToken", "Create a token")
        |> assert_has("#backupToken")

      first = token_on_screen(session)

      session =
        session
        |> click_button("#replaceBackupToken", "Replace the token")
        |> assert_has("#dlgH", text: "Replace the backup token?")
        |> click_button("#dialog-ok", "Replace it")
        |> assert_has("#backupToken")

      second = token_on_screen(session)
      refute second == first

      assert {:ok, %{status: 401}} = fetch("/backup/manifest", first)
      assert {:ok, %{status: 200}} = fetch("/backup/manifest", second)
    end

    test "the allowlist is written on the screen and refuses a typo", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> fill_in("Only these addresses", with: "10.0.0.7", exact: false)
      |> assert_has("#savedSettings", text: "Last saved · just now")

      assert Settings.get(:backup_allowed_ips) == "10.0.0.7"

      conn
      |> open("/admin/settings")
      |> fill_in("Only these addresses", with: "not an address", exact: false)
      |> assert_has("#backupSection", text: "no IP address")

      assert Settings.get(:backup_allowed_ips) == "10.0.0.7"
    end

    test "switching it off closes the door again", %{conn: conn} do
      {:ok, token} = Backup.generate_token()
      {:ok, _} = Settings.put(:backup_enabled, true)

      assert {:ok, %{status: 200}} = fetch("/backup/manifest", token)

      conn
      |> sign_in()
      |> open("/admin/settings")
      |> uncheck("Serve a backup client", exact: false)
      |> assert_has("#savedSettings", text: "Last saved · just now")

      assert {:ok, %{status: 404}} = fetch("/backup/manifest", token)
    end
  end
end
