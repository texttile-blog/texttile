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

  # The browser keeps a picked file until the server has it, so a
  # reload, a closed tab or a phone that dropped the page does not
  # lose it. A file that arrived, or that its admin removed, leaves
  # the browser too.
  describe "a file that has not arrived" do
    @broken_line """
    () => {
      XMLHttpRequest.prototype.send = function () {
        setTimeout(() => this.onerror && this.onerror())
      }
      return true
    }
    """

    # How many files the browser keeps, read straight from IndexedDB,
    # waiting up to five seconds for the expected count. A reload right
    # after a click would race the write.
    @kept_files """
    want => new Promise(resolve => {
      const deadline = Date.now() + 5000
      const look = () => {
        const open = indexedDB.open("texttile-uploads")
        open.onsuccess = () => {
          const count = open.result.transaction("files").objectStore("files").count()
          count.onsuccess = () => {
            open.result.close()
            if (count.result === want || Date.now() > deadline) resolve(count.result)
            else setTimeout(look, 50)
          }
        }
      }
      look()
    })
    """

    test "comes back after a reload and can be sent again", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> evaluate(@broken_line, is_function: true)
      |> upload("Add pictures and videos to the gallery", jpg!("2024:05:01 12:00:00"))
      |> assert_has("#tileLocal .tile.failed", text: "upload failed")
      |> evaluate(@kept_files, [arg: 1, is_function: true], &assert(&1 == 1))
      |> open_editor(article.id)
      |> assert_has("#tileLocal .tile.failed", text: "not uploaded")
      |> click_button("#tileLocal button[data-act=retry]", "Retry")
      |> assert_has("#tileServer [data-id]")
      |> assert_has("#tileCount", text: "1 tile")
      |> evaluate(@kept_files, [arg: 0, is_function: true], &assert(&1 == 0))
      |> open_editor(article.id)
      |> assert_has("#tileServer [data-id]")
      |> refute_has("#tileLocal .tile")

      assert [_] = Gallery.list(article.id)
    end

    test "leaves for good when it is removed", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> evaluate(@broken_line, is_function: true)
      |> upload("Add pictures and videos to the gallery", jpg!("2024:05:01 12:00:00"))
      |> assert_has("#tileLocal .tile.failed", text: "upload failed")
      |> click_button("#tileLocal button[data-act=remove]", "Remove")
      |> refute_has("#tileLocal .tile")
      |> evaluate(@kept_files, [arg: 0, is_function: true], &assert(&1 == 0))
      |> open_editor(article.id)
      |> refute_has("#tileLocal .tile")
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
    test "the lightbox names the pixels and the weight of the original", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> click("#tile-#{a.id}")
      |> assert_has("#lbName", text: "pier.jpg")
      |> assert_has("#lbPixels", text: "40 × 20 px")
      |> assert_has("#lbWeight", text: " KB")
    end

    test "the lightbox picks the preview image and lets it go again", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> assert_has("#tile-#{a.id} .cov")
        |> click("#tile-#{b.id}")
        |> assert_has("#lbPreview:not(:checked)")
        |> check("Preview image")
        |> assert_has("#lbPreview:checked")
        |> assert_has("#tile-#{b.id} .cov")
        |> refute_has("#tile-#{a.id} .cov")

      eventually(fn -> Texttile.Articles.get_article!(article.id).preview_path == b.path end)

      # the first picture speaks again
      conn =
        conn
        |> uncheck("Preview image")
        |> assert_has("#tile-#{a.id} .cov")
        |> assert_has("#lbPreview:not(:checked)")

      eventually(fn -> Texttile.Articles.get_article!(article.id).preview_path == nil end)

      # the first picture is the preview whether ticked or not: the box
      # stays with the server and does not unstick
      conn
      |> click_button("Previous tile")
      |> assert_has("#lbName", text: "pier.jpg")
      |> assert_has("#lbPreview:checked")
      |> uncheck("Preview image")
      |> assert_has("#lbPreview:checked")
      |> assert_has("#tile-#{a.id} .cov")

      # the lightbox's untick asked to choose it, and that stays
      eventually(fn -> Texttile.Articles.get_article!(article.id).preview_path == a.path end)
    end

    test "descriptions autosave, follow remote edits, and clear", %{conn: conn, kb: kb} do
      article = draft!(kb)
      image = seed!(article, "pier.jpg", "2024:05:01 10:00:00")

      session =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> click("#tile-#{image.id}")
        |> fill_in("Description", with: "The pier in the morning.")

      eventually(fn ->
        Gallery.get!(article.id, image.id).description == "The pier in the morning."
      end)

      {:ok, _} = Gallery.set_description(article.id, image.id, "A gull above the pier.")

      session
      |> assert_has("#lbDescription", value: "A gull above the pier.")
      |> fill_in("Description", with: "")
      |> click_button("Close")
      |> refute_has("#lbRoot")

      eventually(fn -> Gallery.get!(article.id, image.id).description == "" end)
    end

    test "navigation saves the description on the tile it belongs to", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> click("#tile-#{a.id}")
      |> fill_in("Description", with: "The pier.")
      |> click_button("Next tile")
      |> assert_has("#lbName", text: "gull.jpg")
      |> assert_has("#lbDescription", value: "")

      eventually(fn -> Gallery.get!(article.id, a.id).description == "The pier." end)
      assert Gallery.get!(article.id, b.id).description == ""
    end

    test "readers see the description in the lightbox", %{conn: conn, kb: kb} do
      article = published_post(user: kb)
      image = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      {:ok, _} = Gallery.set_description(article.id, image.id, "The pier in the morning.")

      conn
      |> open_page(Texttile.Articles.public_path(article))
      |> assert_has("#gal img[alt='The pier in the morning.']")
      |> click("#gal a")
      |> assert_has("#lbCap", text: "The pier in the morning.")
    end

    # The square at the head of the post is a tile shown again: a tap
    # on it opens the lightbox on that tile, not on a copy of it.
    test "the preview square opens the lightbox on its tile", %{conn: conn, kb: kb} do
      article = published_post(user: kb)
      seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      gull = seed!(article, "gull.jpg", "2024:05:01 12:00:00")
      {:ok, _} = Texttile.Articles.update_settings(article, %{preview_path: gull.path})
      {:ok, _} = Gallery.set_description(article.id, gull.id, "A gull above the pier.")

      conn
      |> open_page(Texttile.Articles.public_path(article))
      |> click("#preview")
      |> assert_has("#lbCount", text: "2 / 2")
      |> assert_has("#lbCap", text: "A gull above the pier.")
    end

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
      |> click_button("#lbDelete", "Delete")
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
