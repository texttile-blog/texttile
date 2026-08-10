defmodule TexttileWeb.E2E.BackupClientTest do
  @moduledoc """
  The client that ships in the repository, run against a real server.

  Everything else about the backup is tested from the inside. This is
  the one test that starts `scripts/texttile-backup.sh` as an operator
  starts it, over HTTP, and looks at what lands on the disk.
  """
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Backup
  alias Texttile.Settings
  alias Texttile.Uploads

  @script Path.expand("../../scripts/texttile-backup.sh", __DIR__)

  # The client is written for Debian and Raspberry Pi OS. A developer
  # machine without one of these says so instead of failing.
  @missing Enum.reject(~w(curl jq flock), &System.find_executable/1)

  @moduletag if @missing == [],
               do: [],
               else: [skip: "the backup client needs #{Enum.join(@missing, ", ")}"]

  setup do
    backup_dir =
      Path.join(System.tmp_dir!(), "texttile-backup-test-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(backup_dir) end)

    {:ok, _} = Settings.put(:backup_enabled, true)
    {:ok, token} = Backup.generate_token()

    %{dir: backup_dir, token: token}
  end

  defp write!(relative, content) do
    path = Uploads.absolute(relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    relative
  end

  defp run(%{dir: dir, token: token}) do
    System.cmd(@script, [],
      env: [
        {"TEXTTILE_URL", TexttileWeb.Endpoint.url()},
        {"TEXTTILE_TOKEN", token},
        {"BACKUP_DIR", dir},
        {"TEXTTILE_BACKUP_CONFIG", "/dev/null"}
      ],
      stderr_to_stdout: true
    )
  end

  test "fetches the files and the database, and says what it did", context do
    write!("images/pier-abcd.jpg", "a picture of a pier")
    write!("videos/film-abcd.mp4", "a converted film")
    write!("site/logo-abcd.png", "a mark")
    write!("cache/images__pier-abcd-640.jpg", "a rendition")

    {out, status} = run(context)

    assert status == 0, out
    assert out =~ "3 file(s) in the manifest"
    assert out =~ "files: 3 new, 0 already here"
    assert out =~ "database saved"

    files = Path.join(context.dir, "files")
    assert File.read!(Path.join(files, "images/pier-abcd.jpg")) == "a picture of a pier"
    assert File.read!(Path.join(files, "videos/film-abcd.mp4")) == "a converted film"
    assert File.read!(Path.join(files, "site/logo-abcd.png")) == "a mark"

    # The renditions are made again on demand, so they never travel.
    refute File.exists?(Path.join(files, "cache"))

    # No half-written file is left standing.
    refute File.exists?(Path.join(files, "images/pier-abcd.jpg.part"))

    copy = Path.join([context.dir, "db", "latest.db"])
    assert File.read!(copy) |> binary_part(0, 15) == "SQLite format 3"
  end

  test "a second run fetches nothing it already has", context do
    write!("images/pier-abcd.jpg", "a picture of a pier")

    {_out, 0} = run(context)
    {out, status} = run(context)

    assert status == 0, out
    assert out =~ "files: 0 new, 1 already here"

    # The database comes again every run. Two runs inside one second
    # write one name, because the name carries the second: a client on
    # a daily clock keeps one copy per day.
    assert out =~ "database saved"
    assert Path.wildcard(Path.join([context.dir, "db", "texttile-*.db"])) != []
  end

  test "a file taken off the site stays in the backup", context do
    write!("images/pier-abcd.jpg", "a picture of a pier")

    {_out, 0} = run(context)

    :ok = Uploads.remove("images/pier-abcd.jpg")

    {out, status} = run(context)

    assert status == 0, out
    assert out =~ "0 file(s) in the manifest"

    assert File.read!(Path.join([context.dir, "files", "images", "pier-abcd.jpg"])) ==
             "a picture of a pier"
  end

  test "a wrong token gets nothing, and the run reports a failure", context do
    {out, status} = run(%{context | token: "not the token"})

    refute status == 0
    assert out =~ "could not fetch the manifest"
  end
end
