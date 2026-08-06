defmodule TexttileWeb.ImportLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  alias Texttile.Import.Job
  alias Texttile.Uploads

  setup %{conn: conn} do
    File.rm_rf!(Uploads.root())
    Job.discard()
    on_exit(fn -> Job.discard() end)
    Job.subscribe()
    user = user_fixture(%{username: "kb"})
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the empty page offers the upload", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/edit/settings/import")

    assert html =~ "Import"
    assert has_element?(view, "#import-upload")
  end

  test "settings links here", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/edit/settings")
    assert has_element?(view, "#open-import")
  end

  test "a refused zip shows the failed phase, and Start over clears it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/edit/settings/import")

    path = Path.join(System.tmp_dir!(), "no-zip-#{System.unique_integer([:positive])}")
    File.write!(path, "plain text")
    on_exit(fn -> File.rm_rf!(path) end)

    :ok = Job.validate(path, "no.zip")
    assert_receive {:import_state, %{phase: :failed}}, 2000

    assert render(view) =~ "zip"
    assert has_element?(view, "#import-failed")

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

    {:ok, view, _html} = live(conn, ~p"/edit/settings/import")

    :ok = Job.validate(zip_path, "broken.zip")
    assert_receive {:import_state, %{phase: :report}}, 2000

    assert has_element?(view, "#bundle-broken", "will not import")
    assert has_element?(view, "#import-run[disabled]")

    view |> element("#import-discard") |> render_click()
    assert has_element?(view, "#import-upload")
  end
end
