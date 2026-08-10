defmodule Texttile.BackupTest do
  use Texttile.DataCase, async: false

  alias Texttile.Backup
  alias Texttile.Settings
  alias Texttile.Uploads

  defp write!(relative, content) do
    path = Uploads.absolute(relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp digest(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp by_path(files), do: Map.new(files, &{&1.path, &1})

  describe "the list of files" do
    test "names everything below the root, with its size and its hash" do
      write!("images/one-abcd.jpg", "a picture")
      write!("videos/film-abcd.mp4", "a film")
      write!("site/logo-abcd.png", "a mark")

      files = by_path(Backup.files())

      assert Map.keys(files) |> Enum.sort() == [
               "images/one-abcd.jpg",
               "site/logo-abcd.png",
               "videos/film-abcd.mp4"
             ]

      picture = files["images/one-abcd.jpg"]
      assert picture.size == byte_size("a picture")
      assert picture.sha256 == digest("a picture")
    end

    test "leaves the rendition cache out: it is made again on demand" do
      write!("images/one-abcd.jpg", "a picture")
      write!("cache/images__one-abcd-640.jpg", "a rendition")

      assert ["images/one-abcd.jpg"] = Enum.map(Backup.files(), & &1.path)
    end

    test "an empty installation answers with no files at all" do
      assert Backup.files() == []
    end

    test "hashes one file once and not again" do
      write!("images/one-abcd.jpg", "a picture")
      [%{id: id}] = Backup.files()

      # The stored hash is what a later call answers with, without
      # reading the file again: a manifest must not hash the disk.
      Repo.update_all(
        from(f in "backup_fingerprints", where: f.id == ^id),
        set: [sha256: "not a hash at all"]
      )

      assert [%{sha256: "not a hash at all"}] = Backup.files()
    end

    test "hashes again when the file on disk is another one" do
      write!("images/one-abcd.jpg", "a picture")
      [%{sha256: first}] = Backup.files()

      write!("images/one-abcd.jpg", "another picture entirely")
      [%{sha256: second, size: size}] = Backup.files()

      assert second == digest("another picture entirely")
      assert size == byte_size("another picture entirely")
      refute second == first
    end

    test "forgets a file that has left the disk" do
      write!("images/one-abcd.jpg", "a picture")
      write!("images/two-abcd.jpg", "another")
      assert length(Backup.files()) == 2

      Uploads.remove("images/one-abcd.jpg")

      assert ["images/two-abcd.jpg"] = Enum.map(Backup.files(), & &1.path)
    end
  end

  describe "one file by its id" do
    test "answers with the file the id stands for" do
      write!("images/one-abcd.jpg", "a picture")
      [%{id: id}] = Backup.files()

      assert %{path: "images/one-abcd.jpg"} = Backup.file(id)
    end

    test "answers with nothing for an id nobody has" do
      assert Backup.file(123_456) == nil
      assert Backup.file("not a number") == nil
    end

    test "answers with nothing once the file is gone" do
      write!("images/one-abcd.jpg", "a picture")
      [%{id: id}] = Backup.files()

      Uploads.remove("images/one-abcd.jpg")
      _fresh = Backup.files()

      assert Backup.file(id) == nil
    end
  end

  describe "the switch" do
    test "a fresh installation serves nothing" do
      refute Backup.enabled?()
    end

    test "the switch says whether it serves" do
      {:ok, _} = Settings.put(:backup_enabled, true)
      assert Backup.enabled?()
    end
  end

  describe "the token" do
    test "there is none until one is made" do
      refute Backup.token?()
      refute Backup.valid_token?("anything")
    end

    test "the word is shown once and stored as a hash" do
      {:ok, token} = Backup.generate_token()

      assert byte_size(token) >= 32
      assert Backup.token?()
      assert Backup.valid_token?(token)

      # Whoever reads the database finds no way in.
      refute Settings.get(:backup_token_hash) == token
      refute Settings.get(:backup_token_hash) =~ token
    end

    test "another word does not open it" do
      {:ok, token} = Backup.generate_token()

      refute Backup.valid_token?(token <> "x")
      refute Backup.valid_token?("")
      refute Backup.valid_token?(nil)
    end

    test "a new word takes the old one out of service at once" do
      {:ok, first} = Backup.generate_token()
      {:ok, second} = Backup.generate_token()

      refute first == second
      refute Backup.valid_token?(first)
      assert Backup.valid_token?(second)
    end
  end

  describe "the allowed addresses" do
    test "an empty list lets every address in" do
      assert Backup.allowed_ip?("1.2.3.4")
      assert Backup.allowed_ip?("::1")
    end

    test "a list lets in the addresses on it and no others" do
      {:ok, _} = Settings.put(:backup_allowed_ips, "1.2.3.4, 10.0.0.7")

      assert Backup.allowed_ip?("1.2.3.4")
      assert Backup.allowed_ip?("10.0.0.7")
      refute Backup.allowed_ip?("1.2.3.5")
    end

    test "a list of nothing but spaces lets every address in" do
      {:ok, _} = Settings.put(:backup_allowed_ips, "  ,  ")

      assert Backup.allowed_ip?("1.2.3.4")
    end
  end

  describe "the last access" do
    test "there is none until somebody fetches something" do
      assert Backup.last_access() == nil
    end

    test "the time and the address of the last one are kept" do
      :ok = Backup.note_access("10.0.0.7")

      assert %{at: %DateTime{}, ip: "10.0.0.7"} = Backup.last_access()
    end

    test "only the last one is kept" do
      :ok = Backup.note_access("10.0.0.7")
      :ok = Backup.note_access("10.0.0.8")

      assert %{ip: "10.0.0.8"} = Backup.last_access()
    end
  end

  describe "the copy of the database" do
    test "names the file the installation carries and how big it is" do
      assert %{filename: filename, size: size} = Backup.database()
      assert filename == Path.basename(Repo.config()[:database])
      assert size > 0
    end

    test "hands over a copy that opens as a database, and keeps nothing" do
      {:ok, {path, held}} =
        Backup.copy_database(fn path ->
          assert File.regular?(path)
          assert File.read!(path) |> binary_part(0, 15) == "SQLite format 3"
          {path, File.stat!(path).size}
        end)

      assert held > 0
      refute File.exists?(path)
    end

    test "the copy carries the schema of the installation" do
      {:ok, tables} =
        Backup.copy_database(fn path ->
          {:ok, conn} = Exqlite.Sqlite3.open(path, mode: [:readonly])
          {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master")
          {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, statement)
          :ok = Exqlite.Sqlite3.close(conn)
          List.flatten(rows)
        end)

      assert "settings" in tables
      assert "articles" in tables
    end
  end
end
