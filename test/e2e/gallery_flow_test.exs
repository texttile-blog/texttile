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
      |> assert(contain_text(by_css("#tileCount"), "0 tiles"))
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert_has(by_css("#tileServer [data-id]"))
      |> assert(contain_text(by_css("#tileCount"), "1 tile"))

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
        |> set_input_files(by_label("Add pictures and videos to the gallery"), first)
        |> assert_has(by_css("#tileServer [data-id]"))
        |> set_input_files(by_label("Add pictures and videos to the gallery"), again)
        |> assert(contain_text(by_css("#tileLocal .tile.failed"), "already here"))

      session
      |> assert(contain_text(by_css("#tileNote"), "already in this entry"))
      |> assert(contain_text(by_css("#tileCount"), "1 tile"))
      |> refute_has(by_css("#tileLocal button") |> filter(has_text: "Retry"))

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
      |> set_input_files(by_label("Add pictures and videos to the gallery"), big)
      |> assert_has(by_css("#tileServer [data-id]"), timeout: 30_000)

      assert [_] = Gallery.list(article.id)
    end

    # One roof for a picture and for a film, and Settings > Storage >
    # Upload size limit owns the number. The test moves it down instead of
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
      |> set_input_files(by_label("Add pictures and videos to the gallery"), huge)
      |> assert(contain_text(by_css("#tileLocal .tile.failed"), "10 MB"))
      |> assert_has(by_css("#tileLocal button[data-act=remove]"))
      |> refute_has(by_css("#tileLocal button[data-act=retry]"))

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

    # How many files the browser keeps, read straight from IndexedDB.
    # The assertion asks again until the count is the expected one: a
    # reload right after a click would race the write.
    @kept_files """
    () => new Promise(resolve => {
      const open = indexedDB.open("texttile-uploads")
      open.onsuccess = () => {
        const count = open.result.transaction("files").objectStore("files").count()
        count.onsuccess = () => {
          open.result.close()
          resolve(count.result)
        }
      }
    })
    """

    test "comes back after a reload and can be sent again", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> run_script(@broken_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert(contain_text(by_css("#tileLocal .tile.failed"), "upload failed"))
      |> assert_script(@kept_files, &assert(&1 == 1))
      |> open_editor(article.id)
      |> assert(contain_text(by_css("#tileLocal .tile.failed"), "not uploaded"))
      |> click(by_css("#tileLocal button[data-act=retry]") |> filter(has_text: "Retry"))
      |> assert_has(by_css("#tileServer [data-id]"))
      |> assert(contain_text(by_css("#tileCount"), "1 tile"))
      |> assert_script(@kept_files, &assert(&1 == 0))
      |> open_editor(article.id)
      |> assert_has(by_css("#tileServer [data-id]"))
      |> refute_has(by_css("#tileLocal .tile"))

      assert [_] = Gallery.list(article.id)
    end

    # A phone that dropped the page leaves a row of tiles behind, and
    # one button sends them all instead of a Retry per tile. One tile
    # has its own Retry, so the button waits for a second one.
    test "several go again with one button", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> refute_has(by_css("#tileResume"))
      |> run_script(@broken_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert(count(by_css("#tileLocal .tile.failed"), 1))
      |> refute_has(by_css("#tileResume"))
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:02 12:00:00")
      )
      |> assert(count(by_css("#tileLocal .tile.failed"), 2))
      |> assert_script(@kept_files, &assert(&1 == 2))
      |> open_editor(article.id)
      |> assert(count(by_css("#tileLocal .tile.failed") |> filter(has_text: "not uploaded"), 2))
      |> assert(contain_text(by_css("#tileResume"), "2 uploads did not arrive"))
      |> click(by_css("#tileResume button") |> filter(has_text: "Resume all"))
      |> assert(count(by_css("#tileServer [data-id]"), 2))
      |> refute_has(by_css("#tileLocal .tile"))
      |> refute_has(by_css("#tileResume"))
      |> assert_script(@kept_files, &assert(&1 == 0))

      assert [_, _] = Gallery.list(article.id)
    end

    # The same row of tiles can also go at once: the writer chose the
    # wrong pictures, or does not want them any more.
    test "several leave with one button", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> run_script(@broken_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert(count(by_css("#tileLocal .tile.failed"), 1))
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:02 12:00:00")
      )
      |> assert(count(by_css("#tileLocal .tile.failed"), 2))
      |> assert_script(@kept_files, &assert(&1 == 2))
      |> open_editor(article.id)
      |> assert(contain_text(by_css("#tileResume"), "2 uploads did not arrive"))
      |> click(by_css("#tileResume button") |> filter(has_text: "Remove all"))
      |> refute_has(by_css("#tileLocal .tile"))
      |> refute_has(by_css("#tileResume"))
      |> assert_script(@kept_files, &assert(&1 == 0))
      |> open_editor(article.id)
      |> refute_has(by_css("#tileLocal .tile"))

      assert [] = Gallery.list(article.id)
    end

    # The first tile's size in pixels, once its preview is drawn. The
    # preview is made after the tile, so the assertion asks again until
    # it is there.
    @preview_size """
    () => new Promise(resolve => {
      const tile = document.querySelector("#tileLocal .tile")
      const url = tile && tile.style.backgroundImage.match(/url\\("?(.*?)"?\\)/)
      if (!url) return resolve("no preview yet")
      const img = new Image()
      img.onload = () => resolve([img.naturalWidth, img.naturalHeight])
      img.onerror = () => resolve("broken")
      img.src = url[1]
    })
    """

    # A row of waiting tiles, each with a twelve megapixel photo behind
    # it, made the editor crawl. A tile shows a preview the size of a
    # server tile instead, and so does a tile that comes back.
    test "shows a small preview, not the whole photo", %{conn: conn, kb: kb} do
      article = draft!(kb)
      photo = Path.join(System.tmp_dir!(), "photo-#{System.unique_integer([:positive])}.jpg")
      {:ok, black} = Vix.Vips.Operation.black(4000, 3000)
      :ok = Vix.Vips.Image.write_to_file(black, photo)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> run_script(@broken_line)
      |> set_input_files(by_label("Add pictures and videos to the gallery"), photo)
      |> assert(contain_text(by_css("#tileLocal .tile.failed"), "upload failed"))
      |> assert_script(@preview_size, &assert(&1 == [427, 320]))
      |> assert_script(@kept_files, &assert(&1 == 1))
      |> open_editor(article.id)
      |> assert(contain_text(by_css("#tileLocal .tile.failed"), "not uploaded"))
      |> assert_script(@preview_size, &assert(&1 == [427, 320]))
    end

    # A travelling upload reports its progress many times a second.
    # Only its own tile changes; the others stay the elements they are.
    test "a tile stays put while another one travels", %{conn: conn, kb: kb} do
      article = draft!(kb)

      slow_line = """
      () => {
        XMLHttpRequest.prototype.send = function () {
          let step = 0
          const tick = () => {
            step += 1
            if (step > 5) return this.onerror && this.onerror()
            this.upload.onprogress && this.upload.onprogress({lengthComputable: true, loaded: step, total: 10})
            setTimeout(tick, 30)
          }
          setTimeout(tick)
        }
        return true
      }
      """

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> run_script(@broken_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert(count(by_css("#tileLocal .tile.failed"), 1))
      # its preview is in, so nothing of its own changes it any more
      |> assert_script(@preview_size, &assert(&1 == [40, 20]))
      |> run_script(
        "() => { window.firstTile = document.querySelector('#tileLocal .tile'); return true }"
      )
      |> run_script(slow_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:02 12:00:00")
      )
      |> assert(count(by_css("#tileLocal .tile.failed"), 2))
      |> assert_script("() => window.firstTile.isConnected", &assert(&1 == true))
    end

    # Each progress tick redraws the travelling tile. A keyboard on its
    # Cancel button stays there.
    test "a focused button keeps its focus while its upload travels", %{conn: conn, kb: kb} do
      article = draft!(kb)

      long_line = """
      () => {
        XMLHttpRequest.prototype.send = function () {
          let step = 0
          const tick = () => {
            step += 1
            this.upload.onprogress && this.upload.onprogress({lengthComputable: true, loaded: step % 100, total: 100})
            setTimeout(tick, 20)
          }
          setTimeout(tick)
        }
        return true
      }
      """

      focus_then_look = """
      () => new Promise(resolve => {
        document.querySelector("#tileLocal button[data-act=cancel]").focus()
        setTimeout(() => resolve(document.activeElement.dataset.act || null), 300)
      })
      """

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> run_script(long_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert_has(by_css("#tileLocal .tile.uploading"))
      |> assert_script(focus_then_look, &assert(&1 == "cancel"))
    end

    # The same pictures picked a second time fail as "already here".
    # Nothing can resend them, but they still leave with one button.
    test "several refused tiles leave with one button", %{conn: conn, kb: kb} do
      article = draft!(kb)
      first = jpg!("2024:05:01 12:00:00")

      again = fn ->
        path = Path.join(System.tmp_dir!(), "again-#{System.unique_integer([:positive])}.jpg")
        File.cp!(first, path)
        path
      end

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> set_input_files(by_label("Add pictures and videos to the gallery"), first)
      |> assert_has(by_css("#tileServer [data-id]"))
      |> set_input_files(by_label("Add pictures and videos to the gallery"), again.())
      |> assert(count(by_css("#tileLocal .tile.failed") |> filter(has_text: "already here"), 1))
      |> set_input_files(by_label("Add pictures and videos to the gallery"), again.())
      |> assert(count(by_css("#tileLocal .tile.failed") |> filter(has_text: "already here"), 2))
      |> assert(contain_text(by_css("#tileResume"), "2 uploads did not arrive"))
      |> refute_has(by_css("#tileResume button") |> filter(has_text: "Resume all"))
      |> click(by_css("#tileResume button") |> filter(has_text: "Remove all"))
      |> refute_has(by_css("#tileLocal .tile"))
      |> refute_has(by_css("#tileResume"))

      assert [_only_one] = Gallery.list(article.id)
    end

    test "leaves for good when it is removed", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> run_script(@broken_line)
      |> set_input_files(
        by_label("Add pictures and videos to the gallery"),
        jpg!("2024:05:01 12:00:00")
      )
      |> assert(contain_text(by_css("#tileLocal .tile.failed"), "upload failed"))
      |> click(by_css("#tileLocal button[data-act=remove]") |> filter(has_text: "Remove"))
      |> refute_has(by_css("#tileLocal .tile"))
      |> assert_script(@kept_files, &assert(&1 == 0))
      |> open_editor(article.id)
      |> refute_has(by_css("#tileLocal .tile"))
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
      |> assert(contain_text(by_css("#tileCount"), "3 tiles"))
      |> drag_to(by_css("#tile-#{c.id}"), by_css("#tile-#{a.id}"))

      eventually(fn ->
        Enum.map(Gallery.list(article.id), & &1.id) == [c.id, a.id, b.id]
      end)

      # the numbers followed the drop
      conn |> assert(contain_text(by_css("#tile-#{c.id} .n"), "01"))
    end
  end

  describe "the lightbox" do
    test "the lightbox names the pixels and the weight of the original", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> click(by_css("#tile-#{a.id}"))
      |> assert(contain_text(by_css("#lbName"), "pier.jpg"))
      |> assert(contain_text(by_css("#lbPixels"), "40 × 20 px"))
      |> assert(contain_text(by_css("#lbWeight"), " KB"))
    end

    test "the lightbox picks the preview image and lets it go again", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> assert_has(by_css("#tile-#{a.id} .cov"))
        |> click(by_css("#tile-#{b.id}"))
        |> refute(checked(by_css("#lbPreview")))
        # a click, not check: the box springs back until the server
        # answers, and check fails a box whose click did not tick it
        |> click(by_label("Preview image", exact: true))
        |> assert(checked(by_css("#lbPreview")))
        |> assert_has(by_css("#tile-#{b.id} .cov"))
        |> refute_has(by_css("#tile-#{a.id} .cov"))

      eventually(fn -> Texttile.Articles.get_article!(article.id).preview_path == b.path end)

      # the first picture speaks again
      conn =
        conn
        |> click(by_label("Preview image", exact: true))
        |> assert_has(by_css("#tile-#{a.id} .cov"))
        |> refute(checked(by_css("#lbPreview")))

      eventually(fn -> Texttile.Articles.get_article!(article.id).preview_path == nil end)

      # the first picture is the preview whether ticked or not: the box
      # stays with the server and does not unstick
      conn
      |> click(by_role(:button, name: "Previous tile"))
      |> assert(contain_text(by_css("#lbName"), "pier.jpg"))
      |> assert(checked(by_css("#lbPreview")))
      |> click(by_label("Preview image", exact: true))
      |> assert(checked(by_css("#lbPreview")))
      |> assert_has(by_css("#tile-#{a.id} .cov"))

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
        |> click(by_css("#tile-#{image.id}"))
        |> fill(by_label("Description"), "The pier in the morning.")

      eventually(fn ->
        Gallery.get!(article.id, image.id).description == "The pier in the morning."
      end)

      {:ok, _} = Gallery.set_description(article.id, image.id, "A gull above the pier.")

      session
      |> assert(value(by_css("#lbDescription"), "A gull above the pier."))
      |> fill(by_label("Description"), "")
      |> click(by_role(:button, name: "Close"))
      |> refute_has(by_css("#lbRoot"))

      eventually(fn -> Gallery.get!(article.id, image.id).description == "" end)
    end

    test "navigation saves the description on the tile it belongs to", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> click(by_css("#tile-#{a.id}"))
      |> fill(by_label("Description"), "The pier.")
      |> click(by_role(:button, name: "Next tile"))
      |> assert(contain_text(by_css("#lbName"), "gull.jpg"))
      |> assert(value(by_css("#lbDescription"), ""))

      eventually(fn -> Gallery.get!(article.id, a.id).description == "The pier." end)
      assert Gallery.get!(article.id, b.id).description == ""
    end

    test "readers see the description in the lightbox", %{conn: conn, kb: kb} do
      article = published_post(user: kb)
      image = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      {:ok, _} = Gallery.set_description(article.id, image.id, "The pier in the morning.")

      conn
      |> open_page(Texttile.Articles.public_path(article))
      |> assert_has(by_css("#gal img[alt='The pier in the morning.']"))
      |> click(by_css("#gal a"))
      |> assert(contain_text(by_css("#lbCap"), "The pier in the morning."))
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
        |> assert(contain_text(by_css("#tileCount"), "2 tiles"))
        |> click(by_css("#tileServer [data-id='#{a.id}']"))
        |> assert_has(by_css("#lbRoot"))
        |> assert(contain_text(by_css("#lbName"), "pier.jpg"))
        |> assert(contain_text(by_css("#lbCount"), "1 / 2"))
        |> press(by_css("#lbRoot"), "ArrowRight")
        |> assert(contain_text(by_css("#lbName"), "gull.jpg"))

      # a picture added elsewhere: the count moves, the lightbox stays
      seed!(article, "fog.jpg", "2024:05:01 14:00:00")

      conn
      |> assert(contain_text(by_css("#tileCount"), "3 tiles"))
      |> assert_has(by_css("#lbRoot"))
      |> assert(contain_text(by_css("#lbName"), "gull.jpg"))

      # the date picker resorts the gallery at once
      conn = fill(conn, by_label("Date", exact: true), "2024-05-01T15:00")

      eventually(fn ->
        article.id |> Gallery.list() |> List.last() |> Map.fetch!(:id) == b.id
      end)

      conn
      |> press(by_css("#lbRoot"), "Escape")
      |> refute_has(by_css("#lbRoot"))
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
      |> click(by_css("#tileServer [data-id='#{a.id}']"))
      |> assert_has(by_css("#lbRoot"))
      |> click(by_css("#lbDelete"))
      |> assert(contain_text(by_css("#undoBar"), "pier.jpg"))
      |> assert(contain_text(by_css("#tileCount"), "1 tile"))
      |> assert(contain_text(by_css("#lbName"), "gull.jpg"))
      |> click(by_role(:button, name: "Undo"))
      |> assert(contain_text(by_css("#tileCount"), "2 tiles"))
      |> assert_has(by_css("#tileServer [data-id='#{a.id}']"))

      assert Enum.map(Gallery.list(article.id), & &1.filename) == ["pier.jpg", "gull.jpg"]
    end
  end
end
