defmodule Texttile.ImportTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Gallery
  alias Texttile.Import
  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())
    Req.Test.stub(Texttile.ImportStub, fn conn -> respond_with_jpg(conn) end)
    %{user: user_fixture(), dir: tmp_dir!()}
  end

  defp tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp jpg!(path) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, black} = Vix.Vips.Operation.black(8, 4)
    :ok = Vix.Vips.Image.write_to_file(black, path)
  end

  defp jpg_bytes! do
    path = Path.join(System.tmp_dir!(), "stub-#{System.unique_integer([:positive])}.jpg")
    jpg!(path)
    bytes = File.read!(path)
    File.rm!(path)
    bytes
  end

  defp respond_with_jpg(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("image/jpeg")
    |> Plug.Conn.resp(200, if(conn.method == "HEAD", do: "", else: jpg_bytes!()))
  end

  defp write_bundle(dir, name, front, body \\ "", files \\ []) do
    bundle_dir = Path.join(dir, name)
    Enum.each(files, &jpg!(Path.join(bundle_dir, &1)))
    File.mkdir_p!(bundle_dir)
    File.write!(Path.join(bundle_dir, "index.md"), "---\n#{front}---\n#{body}")
    bundle_dir
  end

  describe "validate/1" do
    test "two bundles with the same slug are an error on both", %{dir: dir} do
      write_bundle(dir, "one", "title: Same\n")
      write_bundle(dir, "two", "title: Same\n")

      report = Import.validate(dir)

      assert [error_one] = Enum.find(report.bundles, &(&1.name == "one")).errors
      assert [error_two] = Enum.find(report.bundles, &(&1.name == "two")).errors
      assert error_one =~ "slug"
      assert error_two =~ "slug"
    end

    test "a slug that exists on the site becomes a warning", %{dir: dir, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_settings(article, %{slug: "beach-days"})

      write_bundle(dir, "beach", "title: Beach days\n")

      report = Import.validate(dir)
      assert [warning] = hd(report.bundles).warnings
      assert warning =~ "update"
    end

    test "a dead URL is an error, a live one is not, and hosts are listed", %{dir: dir} do
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        case conn.host do
          "dead.example" -> Plug.Conn.resp(conn, 404, "")
          _ -> respond_with_jpg(conn)
        end
      end)

      write_bundle(
        dir,
        "beach",
        "title: A\ngallery: [https://live.example/a.jpg, https://dead.example/b.jpg]\n"
      )

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "dead.example/b.jpg"
      assert Enum.sort(report.hosts) == ["dead.example", "live.example"]
    end

    test "a URL that answers without a picture content type is an error", %{dir: dir} do
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.resp(200, "")
      end)

      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/gone]\n")

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "not a picture"
    end

    test "a gallery entry that appears twice is an error", %{dir: dir} do
      write_bundle(dir, "beach", "title: A\ngallery: [a.jpg, a.jpg]\n", "", ["a.jpg"])

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "twice"
    end
  end

  describe "run/2" do
    test "imports a bundle completely", %{dir: dir, user: user} do
      write_bundle(
        dir,
        "beach",
        """
        title: Beach days
        date: 2019-06-02
        tags: [travel, sea]
        type: post
        allow_comments: false
        preview: gallery/bb.jpg
        gallery:
          - gallery/bb.jpg
          - gallery/aa.jpg
          - https://old.example/remote.jpg
        """,
        "The map ![map](map.png) and the first tile again ![bb](gallery/bb.jpg)\n",
        ["gallery/aa.jpg", "gallery/bb.jpg", "map.png"]
      )

      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      summary = Import.run(report, user)
      assert summary.created == 1
      assert summary.updated == 0
      assert summary.failed == []

      article = Repo.get_by!(Article, slug: "beach-days")
      assert article.title == "Beach days"
      assert article.status == "published"
      assert article.publish_date == ~D[2019-06-02]
      assert article.notified_on == ~D[2019-06-02]
      assert article.tags == "travel, sea"
      assert article.allow_comments == false

      # the tiles stand in list order, a second apart
      tiles = Gallery.list(article.id)
      assert Enum.map(tiles, & &1.filename) == ["bb.jpg", "aa.jpg", "remote.jpg"]
      assert Enum.map(tiles, & &1.gallery_date) == Enum.sort(Enum.map(tiles, & &1.gallery_date))

      # the body speaks in upload addresses now
      assert article.body =~ "](/uploads/images/map-"
      refute article.body =~ "](map.png)"

      # the shared source became one upload: the body reuses the tile's file
      [bb | _] = tiles
      assert article.body =~ "](/uploads/#{bb.path})"
      assert article.preview_path == bb.path

      # every file is on disk
      Enum.each([bb.path | Articles.inline_refs(article.body) |> Enum.map(& &1.url)], fn
        "/uploads/" <> relative -> assert File.regular?(Uploads.absolute(relative))
        relative -> assert File.regular?(Uploads.absolute(relative))
      end)

      assert Enum.any?(Articles.log(article), &(&1.text =~ "imported"))
    end

    test "a future date schedules, a draft stays a draft", %{dir: dir, user: user} do
      future = Date.utc_today() |> Date.add(30) |> Date.to_iso8601()
      write_bundle(dir, "soon", "title: Soon\ndate: #{future}\n")
      write_bundle(dir, "quiet", "title: Quiet\nstatus: draft\ndate: 2020-01-01\n")

      Import.run(Import.validate(dir), user)

      assert Repo.get_by!(Article, slug: "soon").status == "scheduled"
      quiet = Repo.get_by!(Article, slug: "quiet")
      assert quiet.status == "draft"
      assert quiet.publish_date == ~D[2020-01-01]
    end

    test "the same zip twice updates instead of duplicating", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: Beach days\ngallery: [a.jpg]\n", "![a](a.jpg)\n", [
        "a.jpg"
      ])

      Import.run(Import.validate(dir), user)
      first = Repo.get_by!(Article, slug: "beach-days")
      old_tile_paths = Gallery.paths(first.id)
      ["/uploads/" <> old_inline] = Articles.inline_refs(first.body) |> Enum.map(& &1.url)

      # the second bundle version drops the gallery and changes the text
      write_bundle(dir, "beach", "title: Beach days again\nslug: beach-days\n", "New body.\n")
      File.rm_rf!(Path.join(dir, "beach/gallery"))
      File.rm_rf!(Path.join(dir, "beach/a.jpg"))

      report = Import.validate(dir)
      summary = Import.run(report, user)
      assert summary.updated == 1
      assert summary.created == 0

      again = Repo.get_by!(Article, slug: "beach-days")
      assert again.id == first.id
      assert again.title == "Beach days again"
      assert Gallery.list(again.id) == []

      # the pictures of the first import are gone, files included
      Enum.each(old_tile_paths, fn path ->
        refute File.regular?(Uploads.absolute(path))
      end)

      refute File.regular?(Uploads.absolute(old_inline))

      # the state before the update stays restorable as a version
      assert Enum.any?(Articles.versions(again), &(&1.title == "Beach days"))
    end

    test "a bundle with errors is skipped, the healthy one imports", %{dir: dir, user: user} do
      write_bundle(dir, "broken", "title: [not, a, scalar]\n")
      write_bundle(dir, "fine", "title: Fine\n")

      summary = Import.run(Import.validate(dir), user)
      assert summary.created == 1
      assert summary.skipped == 1
      assert Repo.get_by(Article, slug: "fine")
    end

    test "a download that dies at run time leaves nothing behind", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/a.jpg]\n")
      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      # the URL died between the dry run and the import
      Req.Test.stub(Texttile.ImportStub, fn conn -> Plug.Conn.resp(conn, 404, "") end)

      summary = Import.run(report, user)
      assert [{"beach", message}] = summary.failed
      assert message =~ "a.jpg"
      refute Repo.get_by(Article, slug: "a")
      assert File.ls(Path.join(Uploads.root(), "images")) in [{:error, :enoent}, {:ok, []}]
    end
  end

  describe "unpack/2" do
    test "unpacks bundles and warns about loose files at the root" do
      source = tmp_dir!()
      write_bundle(source, "beach", "title: A\n")
      File.write!(Path.join(source, "readme.txt"), "hello")
      zip = build_zip(source)

      dest = tmp_dir!()
      assert {:ok, warnings} = Import.unpack(zip, dest)
      assert File.regular?(Path.join(dest, "beach/index.md"))
      assert Enum.any?(warnings, &(&1 =~ "readme.txt"))
    end

    test "refuses an entry that climbs out of the archive", %{dir: dir} do
      zip_path = Path.join(dir, "evil.zip")

      {:ok, _} =
        :zip.create(String.to_charlist(zip_path), [{~c"../evil.txt", "boo"}])

      assert {:error, message} = Import.unpack(zip_path, tmp_dir!())
      assert message =~ "evil.txt"
    end

    test "refuses what is not a zip", %{dir: dir} do
      path = Path.join(dir, "not.zip")
      File.write!(path, "plain text")
      assert {:error, _} = Import.unpack(path, tmp_dir!())
    end
  end

  defp build_zip(source) do
    zip_path = Path.join(tmp_dir!(), "export.zip")

    entries =
      source
      |> Path.join("**")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&String.to_charlist(Path.relative_to(&1, source)))

    {:ok, _} = :zip.create(String.to_charlist(zip_path), entries, cwd: String.to_charlist(source))
    zip_path
  end
end
