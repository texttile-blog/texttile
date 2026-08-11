defmodule Texttile.ExportTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Export
  alias Texttile.Gallery
  alias Texttile.Import
  alias Texttile.Import.Frontmatter
  alias Texttile.Uploads

  # The zip as a map of name to content, which is what every test here
  # asks about.
  defp export!(article) do
    dir = Path.join(System.tmp_dir!(), "export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, path} = Export.write_zip(article, dir)
    {:ok, files} = :zip.unzip(String.to_charlist(path), [:memory])

    Map.new(files, fn {name, content} -> {List.to_string(name), content} end)
  end

  defp index!(files) do
    name = files |> Map.keys() |> Enum.find(&String.ends_with?(&1, "/index.md"))
    {:ok, entries, body} = Frontmatter.parse(Map.fetch!(files, name))
    {entries, body}
  end

  defp tile!(article, name) do
    {:ok, image} = Gallery.add_file(article, jpg_fixture(), name)
    image
  end

  # A picture in the words, stored the way the editor stores one.
  defp in_body!(article, name) do
    {:ok, relative} = Uploads.put_body_image(jpg_fixture(), name, article_id: article.id)
    relative
  end

  describe "the shape of the bundle" do
    test "one folder, named after the address of the entry" do
      article = published_post(%{title: "Beach days", slug: "beach-days"})

      files = export!(article)

      assert Map.has_key?(files, "beach-days/index.md")
      assert Export.zip_name(article) == "beach-days.zip"
    end

    test "an entry without an address falls back to its number" do
      article = draft_post(%{title: ""})

      files = export!(article)

      assert Map.has_key?(files, "entry-#{article.id}/index.md")
      assert Export.zip_name(article) == "entry-#{article.id}.zip"
    end
  end

  describe "the front matter" do
    test "carries what the importer needs to build the entry again" do
      article =
        published_post(%{
          title: "Beach days",
          slug: "beach-days",
          tags: "travel, sea",
          publish_date: ~D[2019-06-02],
          body: "Plain words."
        })

      {entries, body} = index!(export!(article))

      assert entries["title"] == "Beach days"
      assert entries["slug"] == "beach-days"
      assert entries["date"] == "2019-06-02"
      assert entries["status"] == "published"
      assert entries["type"] == "post"
      assert entries["tags"] == ["travel", "sea"]
      assert entries["allow_comments"] == "true"
      assert String.trim(body) == "Plain words."
    end

    test "a quote in the title survives the way out and back" do
      article = published_post(%{title: ~s(The "good" days), slug: "good-days"})

      {entries, _body} = index!(export!(article))

      assert entries["title"] == ~s(The "good" days)
    end

    test "a draft says so, and a scheduled entry keeps its day" do
      draft = draft_post(%{title: "Not yet", slug: "not-yet"})
      later = Date.add(Date.utc_today(), 7)
      scheduled = scheduled_post(%{title: "Soon", slug: "soon", publish_date: later})

      {draft_entries, _} = index!(export!(draft))
      {scheduled_entries, _} = index!(export!(scheduled))

      assert draft_entries["status"] == "draft"
      # The importer schedules what is published with a day still ahead.
      assert scheduled_entries["status"] == "published"
      assert scheduled_entries["date"] == Date.to_iso8601(later)
    end
  end

  describe "the gallery" do
    test "the tiles are numbered in the order the reader meets them" do
      article = published_post(%{title: "Beach days", slug: "beach-days"})
      tile!(article, "beach.jpg")
      tile!(article, "pier.jpg")

      files = export!(article)
      {entries, _body} = index!(files)

      assert entries["gallery"] == ["gallery/001_beach.jpg", "gallery/002_pier.jpg"]
      assert Map.has_key?(files, "beach-days/gallery/001_beach.jpg")
      assert Map.has_key?(files, "beach-days/gallery/002_pier.jpg")
    end

    test "the file that travels is the original, byte for byte" do
      article = published_post(%{title: "Beach days", slug: "beach-days"})
      image = tile!(article, "beach.jpg")

      files = export!(article)

      assert files["beach-days/gallery/001_beach.jpg"] ==
               File.read!(Uploads.absolute(image.path))
    end

    test "the chosen preview is named by its exported path" do
      article = published_post(%{title: "Beach days", slug: "beach-days"})
      tile!(article, "beach.jpg")
      second = tile!(article, "pier.jpg")
      {:ok, article} = Articles.update_settings(article, %{preview_path: second.path})

      {entries, _body} = index!(export!(article))

      assert entries["preview"] == "gallery/002_pier.jpg"
    end
  end

  describe "the pictures in the words" do
    test "travel under xxx_, and the words point at them" do
      article = draft_post(%{title: "Beach days", slug: "beach-days"})
      map = in_body!(article, "map.png")

      {:ok, article} =
        Articles.update_text(article, %{body: "The map:\n\n![The map](/uploads/#{map})"})

      files = export!(article)
      {_entries, body} = index!(files)

      assert Map.has_key?(files, "beach-days/gallery/xxx_001_map.png")
      assert body =~ "![The map](gallery/xxx_001_map.png)"
      refute body =~ "/uploads/"
    end

    test "count up on their own, beside the numbers of the tiles" do
      article = draft_post(%{title: "Beach days", slug: "beach-days"})
      tile!(article, "beach.jpg")
      first = in_body!(article, "map.png")
      second = in_body!(article, "plan.png")

      {:ok, article} =
        Articles.update_text(article, %{
          body: "![one](/uploads/#{first})\n\n![two](/uploads/#{second})"
        })

      files = export!(article)

      assert Map.has_key?(files, "beach-days/gallery/001_beach.jpg")
      assert Map.has_key?(files, "beach-days/gallery/xxx_001_map.png")
      assert Map.has_key?(files, "beach-days/gallery/xxx_002_plan.png")
    end

    test "a reference that climbs out of the uploads carries nothing with it" do
      # A real file right beside the uploads root, and a reference an
      # admin can type by hand to reach it.
      name = "secret-#{System.unique_integer([:positive])}.png"
      secret = Uploads.absolute("../#{name}")
      File.mkdir_p!(Path.dirname(secret))
      File.mkdir_p!(Uploads.absolute("images"))
      File.write!(secret, "not yours")
      on_exit(fn -> File.rm_rf!(secret) end)
      assert File.regular?(Uploads.absolute("images/../../#{name}"))

      climb = "images/../../#{name}"

      article =
        draft_post(%{
          title: "Beach days",
          slug: "beach-days",
          body: "![out](/uploads/#{climb})"
        })

      files = export!(article)
      {_entries, body} = index!(files)

      assert Map.keys(files) == ["beach-days/index.md"]
      assert body =~ "![out](/uploads/#{climb})"
      refute body =~ "gallery/"
    end

    test "a reference to somewhere else is left alone" do
      article =
        draft_post(%{
          title: "Beach days",
          slug: "beach-days",
          body: "![far](https://example.org/far.png)"
        })

      {_entries, body} = index!(export!(article))

      assert body =~ "![far](https://example.org/far.png)"
    end
  end

  describe "the films" do
    test "a film travels as it was uploaded, in the gallery and in the words" do
      article = draft_post(%{title: "Beach days", slug: "beach-days"})
      {:ok, _tile} = Gallery.add_file(article, video_file(320, 240), "harbour.mov")
      {:ok, walk} = Uploads.put_body_video(video_file(320, 240), "walk.mp4")
      {:ok, article} = Articles.update_text(article, %{body: "![walk](/uploads/#{walk})"})

      files = export!(article)
      {entries, body} = index!(files)

      assert Map.has_key?(files, "beach-days/gallery/001_harbour.mov")
      assert Map.has_key?(files, "beach-days/gallery/xxx_001_walk.mp4")
      assert entries["gallery"] == ["gallery/001_harbour.mov"]
      assert body =~ "![walk](gallery/xxx_001_walk.mp4)"
    end
  end

  describe "back through the import" do
    test "the bundle builds the entry again", %{} do
      user = user_fixture()
      article = draft_post(%{title: "Beach days", slug: "beach-days", tags: "travel, sea"})
      tile!(article, "beach.jpg")
      map = in_body!(article, "map.png")

      {:ok, article} =
        Articles.update_text(article, %{body: "The map:\n\n![The map](/uploads/#{map})"})

      dir = Path.join(System.tmp_dir!(), "roundtrip-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, zip} = Export.write_zip(article, dir)

      # The entry steps aside, so the import has to build a new one
      # instead of finding the entry the bundle came from.
      {:ok, _} = Articles.update_settings(article, %{slug: "the-old-one"})

      unpacked = Path.join(dir, "unpacked")
      {:ok, _name} = Import.unpack(zip, unpacked)
      report = Import.validate(unpacked)
      assert [%{errors: []}] = report.bundles
      assert %{created: 1, failed: []} = Import.run(report, user)

      built = Repo.get_by(Texttile.Articles.Article, slug: "beach-days")
      assert built.title == "Beach days"
      assert built.status == "draft"
      assert Articles.tag_list(built) == ["travel", "sea"]
      # The importer stores the bundle file under its own name, so the
      # words point at a fresh upload and at nothing in the bundle.
      assert built.body =~ ~r"!\[The map\]\(/uploads/images/[a-z0-9-]+\.png\)"
      assert [tile] = Gallery.list(built.id)
      assert tile.filename == "001_beach.jpg"
    end
  end

  describe "which text travels" do
    test "a live entry exports the version the readers have" do
      article = published_post(%{title: "Beach days", slug: "beach-days", body: "As published."})
      {:ok, article} = Articles.update_text(article, %{title: "New", body: "Only in the editor."})

      {entries, body} = index!(export!(Articles.get_article!(article.id)))

      assert entries["title"] == "Beach days"
      assert String.trim(body) == "As published."
    end

    test "an entry that was never live exports what stands in the editor" do
      article = draft_post(%{title: "Beach days", slug: "beach-days", body: "Still writing."})

      {entries, body} = index!(export!(article))

      assert entries["title"] == "Beach days"
      assert String.trim(body) == "Still writing."
    end
  end
end
