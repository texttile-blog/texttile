defmodule TexttileWeb.E2E.BackupFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Backup
  alias Texttile.Settings

  # The word is shown once, in a box of its own, and nowhere else. It
  # is read off the live page, because that is where it stands: the
  # first render of this screen carries no token at all.
  defp token_on_screen(session) do
    session |> text_content(by_css("#backupToken")) |> String.trim()
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
      |> assert_has(by_css("#backupSection") |> filter(has_text: "Backup"))
      |> assert(contain_text(by_css("#setBackupNote"), "/backup is closed"))
      # the token and the rest wait behind the switch
      |> refute_has(by_css("#backupLastAccess"))
      |> check(by_label("Allow backups at /backup"))
      |> assert(contain_text(by_css("#backupLastAccess"), "Nothing has been fetched yet"))
      |> uncheck(by_label("Allow backups at /backup"))
      |> refute_has(by_css("#backupLastAccess"))

      refute Backup.enabled?()
      refute Backup.token?()
    end

    test "the owner switches it on, makes a token, and a client fetches with it", %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> open("/admin/settings")
        |> check(by_label("Allow backups at /backup"))
        # the toast is the save answering
        |> assert(contain_text(by_css("#toast"), "Saved"))
        |> click(by_css("#makeBackupToken"))
        |> assert_has(by_css("#backupToken"))

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
      |> assert(contain_text(by_css("#backupLastAccess"), "127.0.0.1"))
      # The word itself is gone from the screen: it is kept as a hash.
      |> refute_has(by_css("#backupToken"))
      |> assert(contain_text(by_css("#backupTokenState"), "A token is in service"))
    end

    # The word is shown once and has to reach a configuration file
    # somewhere else, so it is handed over the way the share lines are:
    # touching it picks all of it, and Copy says what it did.
    @token_selected """
    () => {
      const field = document.querySelector("#backupToken")
      return field.selectionEnd - field.selectionStart === field.value.length
    }
    """

    test "the token is picked whole by a touch, and Copy says it copied", %{conn: conn} do
      conn
      |> sign_in()
      |> open("/admin/settings")
      |> check(by_label("Allow backups at /backup"))
      |> click(by_css("#makeBackupToken"))
      |> assert_has(by_css("#backupToken"))
      |> focus(by_css("#backupToken"))
      |> assert_script(@token_selected, &assert(&1 == true))
      |> click(by_css("#copyBackupToken"))
      |> assert(contain_text(by_css("#copyBackupToken"), "Copied"))
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

    test "copies over plain http, where the page has no clipboard object", %{conn: conn} do
      session =
        conn
        |> add_init_script(@no_clipboard)
        |> sign_in()
        |> open("/admin/settings")
        |> check(by_label("Allow backups at /backup"))
        |> click(by_css("#makeBackupToken"))
        |> assert_has(by_css("#backupToken"))

      token = token_on_screen(session)

      session
      |> click(by_css("#copyBackupToken"))
      |> assert(contain_text(by_css("#copyBackupToken"), "Copied"))
      |> click(by_css("#setting-backup_allowed_ips"))
      |> press(by_css("#setting-backup_allowed_ips"), "ControlOrMeta+v")
      |> assert(value(by_css("#setting-backup_allowed_ips"), token))
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
      conn
      |> add_init_script(@counting_clipboard)
      |> sign_in()
      |> open("/admin/settings")
      |> check(by_label("Allow backups at /backup"))
      |> click(by_css("#makeBackupToken"))
      |> assert_has(by_css("#backupToken"))
      |> uncheck(by_label("Allow backups at /backup"))
      |> assert(contain_text(by_css("#setBackupNote"), "/backup is closed"))
      |> check(by_label("Allow backups at /backup"))
      |> assert(contain_text(by_css("#setBackupNote"), "may fetch"))
      |> click(by_css("#copyBackupToken"))
      |> assert(contain_text(by_css("#copyBackupToken"), "Copied"))
      |> assert_script(@writes, &assert(&1 == 1))
    end

    test "a new token takes the old one out of service, once it is confirmed", %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> open("/admin/settings")
        |> check(by_label("Allow backups at /backup"))
        |> click(by_css("#makeBackupToken"))
        |> assert_has(by_css("#backupToken"))

      first = token_on_screen(session)

      session =
        session
        |> click(by_css("#replaceBackupToken"))
        |> assert(contain_text(by_css("#dlgH"), "Replace the backup token?"))
        |> click(by_css("#dialog-ok"))
        |> assert_has(by_css("#backupToken"))

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
        |> check(by_label("Allow backups at /backup"))
        |> click(by_css("#makeBackupToken"))
        |> assert_has(by_css("#backupToken"))

      token = token_on_screen(session)

      session
      |> click(by_css("#replaceBackupToken"))
      |> assert(contain_text(by_css("#dlgH"), "Replace the backup token?"))
      |> click(by_css("#dialog-cancel"))
      |> refute_has(by_css("#dlgH"))
      |> assert(contain_text(by_css("#backupTokenState"), "A token is in service"))

      assert {:ok, %{status: 200}} = fetch("/backup/manifest", token)
    end
  end
end
