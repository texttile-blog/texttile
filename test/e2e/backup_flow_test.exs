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
        # the loud line is the save answering; its quiet stamp only
        # returns after the flash has faded, and that is 2.6 seconds
        |> assert_has("#savedSettings.fresh")
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

    # The word is shown once and has to reach a configuration file
    # somewhere else, so it is handed over the way the share lines are:
    # touching it picks all of it, and Copy says what it did.
    @token_selected """
    () => {
      const field = document.querySelector("#backupToken")
      field.focus()
      return field.selectionEnd - field.selectionStart === field.value.length
    }
    """

    test "the token is picked whole by a touch, and Copy says it copied", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> check("Serve a backup client", exact: false)
      |> click_button("#makeBackupToken", "Create a token")
      |> assert_has("#backupToken")
      |> evaluate(@token_selected, [is_function: true], &assert(&1 == true))
      |> click_button("#copyBackupToken", "Copy")
      |> assert_has("#copyBackupToken", text: "Copied")
    end

    # A page with no clipboard object at all, which is what a browser
    # gives a blog served over plain http: the address of a machine in
    # the house is not a secure origin, and there `navigator.clipboard`
    # is not a permission that can be refused, it is simply absent.
    # Copy has to reach the clipboard by the old way then, and it may
    # only say it copied if it did.
    @no_clipboard """
    Object.defineProperty(navigator, "clipboard", {value: undefined})
    """

    # Asking the page whether it copied proves nothing: the button said
    # "Copied" while nothing had been copied at all. So the test pastes
    # into a field of the same screen and reads what arrives.
    @pasted "() => document.querySelector('#setting-backup_allowed_ips').value"

    test "copies over plain http, where the page has no clipboard object", %{conn: conn} do
      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(conn.context_id,
          source: @no_clipboard,
          timeout: 5_000
        )

      session =
        conn
        |> sign_in()
        |> open("/admin/settings")
        |> check("Serve a backup client", exact: false)
        |> click_button("#makeBackupToken", "Create a token")
        |> assert_has("#backupToken")

      token = token_on_screen(session)

      session
      |> click_button("#copyBackupToken", "Copy")
      |> assert_has("#copyBackupToken", text: "Copied")
      |> click("#setting-backup_allowed_ips")
      |> press("#setting-backup_allowed_ips", "ControlOrMeta+v")
      |> evaluate(@pasted, [is_function: true], &assert(&1 == token))
    end

    # A clipboard that counts what it is handed. The page has none on
    # plain http, so this is also the only way to see the writing at
    # all.
    @counting_clipboard """
    window.__writes = 0
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: () => { window.__writes++; return Promise.resolve() } },
    })
    """

    @writes "() => window.__writes"

    # The screen redraws around the button all the time: a setting
    # saved here or in another tab redraws it. A hook that wired the
    # button again on every redraw would hand the word over once per
    # redraw, and nothing on the screen would say so.
    test "copies once, however often the screen has been redrawn", %{conn: conn} do
      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(conn.context_id,
          source: @counting_clipboard,
          timeout: 5_000
        )

      conn
      |> sign_in()
      |> open("/admin/settings")
      |> check("Serve a backup client", exact: false)
      |> click_button("#makeBackupToken", "Create a token")
      |> assert_has("#backupToken")
      |> uncheck("Serve a backup client", exact: false)
      |> assert_has("#setBackupNote", text: "answers nothing")
      |> check("Serve a backup client", exact: false)
      |> assert_has("#setBackupNote", text: "may fetch")
      |> click_button("#copyBackupToken", "Copy")
      |> assert_has("#copyBackupToken", text: "Copied")
      |> evaluate(@writes, [is_function: true], &assert(&1 == 1))
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

    test "cancelling the question leaves the token in service", %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> open("/admin/settings")
        |> check("Serve a backup client", exact: false)
        |> click_button("#makeBackupToken", "Create a token")
        |> assert_has("#backupToken")

      token = token_on_screen(session)

      session
      |> click_button("#replaceBackupToken", "Replace the token")
      |> assert_has("#dlgH", text: "Replace the backup token?")
      |> click_button("#dialog-cancel", "Cancel")
      |> refute_has("#dlgH")
      |> assert_has("#backupTokenState", text: "A token is in service")

      assert {:ok, %{status: 200}} = fetch("/backup/manifest", token)
    end
  end
end
