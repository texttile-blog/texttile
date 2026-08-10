defmodule TexttileWeb.BackupControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Backup
  alias Texttile.Settings
  alias Texttile.Uploads

  defp write!(relative, content) do
    path = Uploads.absolute(relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    relative
  end

  defp serving do
    {:ok, _} = Settings.put(:backup_enabled, true)
    {:ok, token} = Backup.generate_token()
    token
  end

  defp with_token(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "while the backup API is switched off" do
    test "the manifest is not there at all", %{conn: conn} do
      assert conn |> get(~p"/backup/manifest") |> response(404)
    end

    test "not even for somebody holding a token", %{conn: conn} do
      {:ok, token} = Backup.generate_token()

      assert conn |> with_token(token) |> get(~p"/backup/manifest") |> response(404)
    end

    test "and neither is the database or a file", %{conn: conn} do
      assert conn |> get(~p"/backup/db") |> response(404)
      assert conn |> get(~p"/backup/file/1") |> response(404)
    end
  end

  describe "the way in" do
    setup do
      %{token: serving()}
    end

    test "without a word nothing is served", %{conn: conn} do
      conn = get(conn, ~p"/backup/manifest")

      assert response(conn, 401)
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "the wrong word is no word", %{conn: conn} do
      assert conn |> with_token("wrong") |> get(~p"/backup/manifest") |> response(401)
    end

    test "a word in the address is no word: it lands in every log there is", %{
      conn: conn,
      token: token
    } do
      assert conn |> get(~p"/backup/manifest?token=#{token}") |> response(401)
    end

    test "a token but no switch is still nothing", %{conn: conn, token: token} do
      {:ok, _} = Settings.put(:backup_enabled, false)

      assert conn |> with_token(token) |> get(~p"/backup/manifest") |> response(404)
    end

    test "an installation with the switch on but no token serves nobody", %{conn: conn} do
      :ok = Backup.clear_token()

      assert conn |> with_token("") |> get(~p"/backup/manifest") |> response(401)
    end

    test "an address off the allowlist finds nothing there", %{conn: conn, token: token} do
      {:ok, _} = Settings.put(:backup_allowed_ips, "10.9.9.9")

      assert conn |> with_token(token) |> get(~p"/backup/manifest") |> response(404)
    end

    test "an address on the allowlist is served", %{conn: conn, token: token} do
      {:ok, _} = Settings.put(:backup_allowed_ips, "127.0.0.1, 10.9.9.9")

      assert conn |> with_token(token) |> get(~p"/backup/manifest") |> json_response(200)
    end

    test "a fetch is remembered, so the settings screen can say backups run", %{
      conn: conn,
      token: token
    } do
      assert Backup.last_access() == nil

      conn |> with_token(token) |> get(~p"/backup/manifest") |> json_response(200)

      assert %{ip: "127.0.0.1"} = Backup.last_access()
    end

    test "a caller who knocks all day is turned away", %{conn: conn, token: token} do
      limit = Backup.limiter_per_minute()

      for _ <- 1..limit do
        assert conn |> with_token(token) |> get(~p"/backup/manifest") |> json_response(200)
      end

      assert conn |> with_token(token) |> get(~p"/backup/manifest") |> response(429)
    end
  end

  describe "the manifest" do
    setup do
      %{token: serving()}
    end

    test "says what the installation holds", %{conn: conn, token: token} do
      write!("images/one-abcd.jpg", "a picture")

      body = conn |> with_token(token) |> get(~p"/backup/manifest") |> json_response(200)

      assert {:ok, _stamp, _offset} = DateTime.from_iso8601(body["generated_at"])
      assert body["texttile_version"] == Texttile.version()
      assert body["database"]["filename"] =~ ".db"
      assert body["database"]["size"] > 0

      assert [file] = body["files"]
      assert file["path"] == "images/one-abcd.jpg"
      assert file["size"] == byte_size("a picture")
      assert file["sha256"] == Base.encode16(:crypto.hash(:sha256, "a picture"), case: :lower)
      assert is_integer(file["id"])
    end

    test "carries the originals and what ffmpeg made, and no rendition", %{
      conn: conn,
      token: token
    } do
      write!("images/one-abcd.jpg", "a picture")
      write!("videos/film-abcd.mov", "a film")
      write!("videos/film-abcd.mp4", "the converted film")
      write!("site/logo-abcd.png", "a mark")
      write!("cache/images__one-abcd-640.jpg", "a rendition")

      body = conn |> with_token(token) |> get(~p"/backup/manifest") |> json_response(200)

      assert Enum.map(body["files"], & &1["path"]) == [
               "images/one-abcd.jpg",
               "site/logo-abcd.png",
               "videos/film-abcd.mov",
               "videos/film-abcd.mp4"
             ]
    end

    test "an empty installation answers with an empty list", %{conn: conn, token: token} do
      body = conn |> with_token(token) |> get(~p"/backup/manifest") |> json_response(200)

      assert body["files"] == []
    end
  end

  describe "one file" do
    setup do
      %{token: serving()}
    end

    test "comes back byte for byte", %{conn: conn, token: token} do
      write!("images/one-abcd.jpg", "a picture")
      [%{id: id}] = Backup.files()

      conn = conn |> with_token(token) |> get(~p"/backup/file/#{id}")

      assert response(conn, 200) == "a picture"
      assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end

    test "an id nobody has is not found", %{conn: conn, token: token} do
      assert conn |> with_token(token) |> get(~p"/backup/file/98765") |> response(404)
    end

    test "an id that is no number is not found", %{conn: conn, token: token} do
      assert conn |> with_token(token) |> get(~p"/backup/file/etc-passwd") |> response(404)
    end

    test "a file that has left the disk is not found", %{conn: conn, token: token} do
      write!("images/one-abcd.jpg", "a picture")
      [%{id: id}] = Backup.files()
      Uploads.remove("images/one-abcd.jpg")

      assert conn |> with_token(token) |> get(~p"/backup/file/#{id}") |> response(404)
    end

    test "no path of the caller's choosing is ever followed", %{conn: conn, token: token} do
      # There is no route that takes a path, and a path in the id is
      # not a number, so it resolves to nothing.
      assert conn |> with_token(token) |> get(~p"/backup/file/..%2F..%2Fdb") |> response(404)
    end
  end

  describe "the database" do
    setup do
      %{token: serving()}
    end

    test "comes as a file that opens as a database", %{conn: conn, token: token} do
      conn = conn |> with_token(token) |> get(~p"/backup/db")

      body = response(conn, 200)
      assert binary_part(body, 0, 15) == "SQLite format 3"
      assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
      assert [name] = get_resp_header(conn, "content-disposition")
      assert name =~ ".db"
    end

    test "leaves no copy behind", %{conn: conn, token: token} do
      folder = Texttile.Repo.config()[:database] |> Path.dirname()
      before = File.ls!(folder)

      conn |> with_token(token) |> get(~p"/backup/db") |> response(200)

      assert File.ls!(folder) -- before == []
    end
  end
end
