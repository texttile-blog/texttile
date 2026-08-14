defmodule TexttileWeb.ImportLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  alias Texttile.Import.Job

  setup %{conn: conn} do
    Job.discard()
    on_exit(fn -> Job.discard() end)
    Job.subscribe()
    user = user_fixture(%{username: "kb"})
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the empty page offers the upload", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/settings/import")

    assert html =~ "Import"
    assert has_element?(view, "#import-upload")
  end

  test "settings links here", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/settings")
    assert has_element?(view, "#open-import")
  end

  test "a refused zip shows the failed phase, and Start over clears it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/settings/import")

    path = Path.join(System.tmp_dir!(), "no-zip-#{System.unique_integer([:positive])}")
    File.write!(path, "plain text")
    on_exit(fn -> File.rm_rf!(path) end)

    :ok = Job.validate(path, "no.zip")
    assert_receive {:import_state, %{phase: :failed}}, 2000

    # This test and the page are two listeners on one topic, and the
    # message reaching this one says nothing about the other, so the
    # page gets its own moment to catch up.
    #
    # What stood here was `render(view) =~ "zip"`, which is true on the
    # empty page as well: the upload hint says zip, and so does
    # "Reading no.zip …" while it reads. The assertion could not fail,
    # and the phase went unchecked. This block stands in the failed
    # phase and nowhere else, and it carries the reason with it.
    eventually(fn -> has_element?(view, "#import-failed", "not a zip archive") end)

    view |> element("#import-discard") |> render_click()
    assert has_element?(view, "#import-upload")
  end

  test "a report with nothing importable keeps the button disabled", %{conn: conn} do
    source = Path.join(System.tmp_dir!(), "live-zip-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(source, "broken"))
    File.write!(Path.join(source, "broken/index.md"), "---\ntype: page\n---\n")
    zip_path = Path.join(System.tmp_dir!(), "live-#{System.unique_integer([:positive])}.zip")

    {:ok, _} =
      :zip.create(String.to_charlist(zip_path), [~c"broken/index.md"],
        cwd: String.to_charlist(source)
      )

    on_exit(fn ->
      File.rm_rf!(source)
      File.rm_rf!(zip_path)
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/settings/import")

    :ok = Job.validate(zip_path, "broken.zip")
    assert_receive {:import_state, %{phase: :report}}, 2000

    # As above: the page hears the same broadcast on its own account.
    eventually(fn -> has_element?(view, "#bundle-broken", "will not import") end)
    assert has_element?(view, "#import-run[disabled]")

    view |> element("#import-discard") |> render_click()
    assert has_element?(view, "#import-upload")
  end

  test "the page names the upload roof from the settings and the room left", %{conn: conn} do
    {:ok, _value} = Texttile.Settings.put(:max_upload_mb, 700)

    {:ok, view, html} = live(conn, ~p"/admin/settings/import")

    assert html =~ "700 MB"
    assert has_element?(view, "#import-room")
  end

  test "a zip past the roof says so instead of standing at 0%", %{conn: conn} do
    {:ok, _value} = Texttile.Settings.put(:max_upload_mb, 10)

    {:ok, view, _html} = live(conn, ~p"/admin/settings/import")

    upload =
      file_input(view, "#import-upload", :zip, [
        %{
          name: "big.zip",
          content: :binary.copy("z", 10_500_000),
          type: "application/zip"
        }
      ])

    assert {:error, [[_ref, :too_large]]} = render_upload(upload, "big.zip")
    assert render(view) =~ "10 MB"
    assert has_element?(view, "#import-upload", "larger")
  end
end
