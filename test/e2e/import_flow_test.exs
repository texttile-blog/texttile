defmodule TexttileWeb.E2E.ImportFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles.Article
  alias Texttile.Gallery
  alias Texttile.Repo
  alias Texttile.Uploads

  test "a zip of bundles becomes texts, tiles included", %{conn: conn} do
    zip = build_zip()

    conn
    |> sign_in()
    |> click_button("#wmBtn", "Texttile")
    # the menu opens in the browser: wait for it, or the next click
    # races the script on a slow machine
    |> assert_has("#navMenu", text: "Settings")
    |> click_link("Settings")
    |> click_link("#open-import", "Open the import")
    |> assert_has("#crumb", text: "Import")
    |> upload("#import-upload input[type=file]", "Upload the zip", zip, exact: false)
    |> assert_has("#import-report", text: "The report")
    |> assert_has("#bundle-beach", text: "will import")
    |> assert_has("#bundle-beach", text: "2 comments")
    |> assert_has("#bundle-beach", text: "nothing references stray.txt")
    |> assert_has("#bundle-broken", text: "will not import")
    |> click_button("#import-run", "Import 1 entry")
    |> assert_has("#import-summary", text: "1 created")
    |> click_button("#import-done", "Done")
    |> assert_has("#import-upload", text: "Upload the zip")

    article = Repo.get_by!(Article, slug: "beach-days")
    assert article.title == "Beach days"
    assert article.status == "published"
    assert article.body =~ "](/uploads/images/map-"

    assert [tile_b, tile_a] = Gallery.list(article.id)
    assert tile_b.filename == "b.jpg"
    assert tile_a.filename == "a.jpg"
    assert File.regular?(Uploads.absolute(tile_b.path))

    # the imported text stands in the texts grid
    conn
    |> open_page("/")
    |> assert_has("body", text: "Beach days")

    # and its comments stand under it, the answer behind the comment it
    # answers, the name carrying the address its author gave back then
    conn
    |> open_page(Texttile.Articles.public_path(article))
    |> assert_has("#comments", text: "Ihr Lieben, immer wieder!")
    |> assert_has("#comments", text: "Danke euch!")
    |> assert_has("#comments a[href='https://christiane.example']", text: "Christiane")

    [christiane, kb] = elem(Texttile.Comments.for_readers(article.id), 0)
    assert christiane.name == "Christiane"
    assert kb.name == "kb"
  end

  defp build_zip do
    source = Path.join(System.tmp_dir!(), "e2e-import-#{System.unique_integer([:positive])}")

    write_jpg = fn relative ->
      path = Path.join(source, relative)
      File.mkdir_p!(Path.dirname(path))
      {:ok, black} = Vix.Vips.Operation.black(8, 4)
      :ok = Vix.Vips.Image.write_to_file(black, path)
    end

    write_jpg.("beach/gallery/a.jpg")
    write_jpg.("beach/gallery/b.jpg")
    write_jpg.("beach/map.png")
    File.write!(Path.join(source, "beach/stray.txt"), "left over")

    File.write!(Path.join(source, "beach/index.md"), """
    ---
    title: Beach days
    date: 2019-06-02
    tags: [travel, sea]
    gallery:
      - gallery/b.jpg
      - gallery/a.jpg
    ---
    The map ![map](map.png) of the trip.
    """)

    File.write!(Path.join(source, "beach/comments.yaml"), """
    - author: Christiane
      email: christiane@example.org
      website: https://christiane.example
      date: 2019-06-03 22:14
      id: 12
      text: |
        Ihr Lieben, immer wieder!

        Es war ein Fest mit euren Jungs.
    - author: kb
      date: 2019-06-04 09:02
      reply_to: 12
      text: |
        Danke euch!
    """)

    File.mkdir_p!(Path.join(source, "broken"))
    File.write!(Path.join(source, "broken/index.md"), "---\ntype: page\n---\n")

    zip_path =
      Path.join(System.tmp_dir!(), "e2e-import-#{System.unique_integer([:positive])}.zip")

    entries =
      source
      |> Path.join("**")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&String.to_charlist(Path.relative_to(&1, source)))

    {:ok, _} =
      :zip.create(String.to_charlist(zip_path), entries, cwd: String.to_charlist(source))

    on_exit(fn ->
      File.rm_rf!(source)
      File.rm_rf!(zip_path)
    end)

    zip_path
  end
end
