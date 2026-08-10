defmodule TexttileWeb.E2E.GalleryFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Gallery

  # A real JPEG on disk, with a capture date the gallery can read.
  defp jpg!(taken) do
    path = Path.join(System.tmp_dir!(), "e2e-#{System.unique_integer([:positive])}.jpg")
    {:ok, black} = Vix.Vips.Operation.black(40, 20)

    {:ok, image} =
      Vix.Vips.Image.mutate(black, fn mut ->
        :ok = Vix.Vips.MutableImage.set(mut, "exif-ifd2-DateTimeOriginal", :gchararray, taken)
      end)

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end

  defp seed!(article, name, taken) do
    {:ok, image} = Gallery.add_file(article, jpg!(taken), name)
    image
  end

  describe "uploading" do
    test "a picked file becomes a tile, the count follows", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> assert_has("#tileCount", text: "0 tiles")
      |> upload("Add pictures and videos to the gallery", jpg!("2024:05:01 12:00:00"))
      |> assert_has("#tileServer [data-id]")
      |> assert_has("#tileCount", text: "1 tile")

      assert [%{filename: "e2e-" <> _}] = Gallery.list(article.id)
    end

    # An entry takes each picture once. The tile says so in three
    # words and offers only Remove; the row over the grid names the
    # picture it already is.
    test "the same picture a second time is refused, and named", %{conn: conn, kb: kb} do
      article = draft!(kb)
      first = jpg!("2024:05:01 12:00:00")
      again = Path.join(System.tmp_dir!(), "again-#{System.unique_integer([:positive])}.jpg")
      File.cp!(first, again)

      session =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> upload("Add pictures and videos to the gallery", first)
        |> assert_has("#tileServer [data-id]")
        |> upload("Add pictures and videos to the gallery", again)
        |> assert_has("#tileLocal .tile.failed", text: "already here")

      session
      |> assert_has("#tileNote", text: "already in this entry")
      |> assert_has("#tileCount", text: "1 tile")
      |> refute_has("#tileLocal button", text: "Retry")

      assert [_only_one] = Gallery.list(article.id)
    end

    test "a photo far past the old 8 MB parser default arrives", %{conn: conn, kb: kb} do
      article = draft!(kb)

      big = Path.join(System.tmp_dir!(), "big-#{System.unique_integer([:positive])}.jpg")
      {:ok, noise} = Vix.Vips.Operation.gaussnoise(4000, 3000, sigma: 40.0)
      {:ok, bands} = Vix.Vips.Operation.bandjoin([noise, noise, noise])
      {:ok, cast} = Vix.Vips.Operation.cast(bands, :VIPS_FORMAT_UCHAR)
      :ok = Vix.Vips.Image.write_to_file(cast, big, Q: 95)
      assert File.stat!(big).size > 9_000_000

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> upload("Add pictures and videos to the gallery", big)
      |> assert_has("#tileServer [data-id]", timeout: 30_000)

      assert [_] = Gallery.list(article.id)
    end

    # One roof for a picture and for a film, and Settings > Storage >
    # Biggest upload owns the number. The test moves it down instead of
    # making a half-gigabyte file, and that is the point of the test:
    # the browser reads the roof off the page.
    test "a file past the roof fails on the spot, nothing travels", %{conn: conn, kb: kb} do
      article = draft!(kb)
      {:ok, _} = Texttile.Settings.put(:max_upload_mb, 10)

      huge = Path.join(System.tmp_dir!(), "huge-#{System.unique_integer([:positive])}.jpg")
      {:ok, file} = File.open(huge, [:write])
      :ok = :file.pwrite(file, 11 * 1024 * 1024, <<0>>)
      :ok = File.close(file)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> upload("Add pictures and videos to the gallery", huge)
      |> assert_has("#tileLocal .tile.failed", text: "10 MB")
      |> assert_has("#tileLocal button[data-act=remove]")
      |> refute_has("#tileLocal button[data-act=retry]")

      assert Gallery.list(article.id) == []
    end
  end

  describe "sorting" do
    test "a mouse drag over the tiles writes a new order", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "a.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "b.jpg", "2024:05:01 12:00:00")
      c = seed!(article, "c.jpg", "2024:05:01 14:00:00")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> assert_has("#tileCount", text: "3 tiles")
      |> drag("#tile-#{c.id}", to: "#tile-#{a.id}")

      eventually(fn ->
        Enum.map(Gallery.list(article.id), & &1.id) == [c.id, a.id, b.id]
      end)

      # the numbers followed the drop
      conn |> assert_has("#tile-#{c.id} .n", text: "01")
    end
  end

  describe "the lightbox" do
    test "opens on a tap, navigates, edits, and survives background changes",
         %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> assert_has("#tileCount", text: "2 tiles")
        |> click("#tileServer [data-id='#{a.id}']")
        |> assert_has("#lbRoot")
        |> assert_has("#lbName", text: "pier.jpg")
        |> assert_has("#lbCount", text: "1 / 2")
        |> press("#lbRoot", "ArrowRight")
        |> assert_has("#lbName", text: "gull.jpg")

      # a picture added elsewhere: the count moves, the lightbox stays
      seed!(article, "fog.jpg", "2024:05:01 14:00:00")

      conn
      |> assert_has("#tileCount", text: "3 tiles")
      |> assert_has("#lbRoot")
      |> assert_has("#lbName", text: "gull.jpg")

      # the date picker resorts the gallery at once
      conn = fill_in(conn, "Date", with: "2024-05-01T15:00")

      eventually(fn ->
        article.id |> Gallery.list() |> List.last() |> Map.fetch!(:id) == b.id
      end)

      conn
      |> press("#lbRoot", "Escape")
      |> refute_has("#lbRoot")
    end
  end

  describe "delete and the way back" do
    test "the tile leaves at once and undo puts it back", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      _b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> click("#tileServer [data-id='#{a.id}']")
      |> assert_has("#lbRoot")
      |> click_button("Delete tile")
      |> assert_has("#undoBar", text: "pier.jpg")
      |> assert_has("#tileCount", text: "1 tile")
      |> assert_has("#lbName", text: "gull.jpg")
      |> click_button("Undo")
      |> assert_has("#tileCount", text: "2 tiles")
      |> assert_has("#tileServer [data-id='#{a.id}']")

      assert Enum.map(Gallery.list(article.id), & &1.filename) == ["pier.jpg", "gull.jpg"]
    end
  end
end
