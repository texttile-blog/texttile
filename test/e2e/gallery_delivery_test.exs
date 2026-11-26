defmodule TexttileWeb.E2E.GalleryDeliveryTest do
  use TexttileWeb.E2E

  alias Texttile.Gallery

  defp pictures!(article) do
    for hour <- 10..13 do
      path = Path.join(System.tmp_dir!(), "lightbox-#{System.unique_integer([:positive])}.jpg")
      {:ok, image} = Vix.Vips.Operation.black(2800, 1800)

      {:ok, image} =
        Vix.Vips.Image.mutate(image, fn mut ->
          :ok =
            Vix.Vips.MutableImage.set(
              mut,
              "exif-ifd2-DateTimeOriginal",
              :gchararray,
              "2024:05:01 #{hour}:00:00"
            )
        end)

      :ok = Vix.Vips.Image.write_to_file(image, path)
      {:ok, tile} = Gallery.add_file(article, path, "#{hour}.jpg")
      File.rm!(path)
      tile
    end
  end

  # Which tiles the browser has fetched at the size of the one in the
  # lightbox, that one's address, and what it fetched at the largest
  # size. The assertion asks again until the fetches it waits for are in.
  @fetched """
  () => {
    const tiles = [...document.querySelectorAll('#tileServer [data-id]')];
    const img = document.querySelector('#lbImg img');
    const current = img?.currentSrc || "";
    const size = current && new URL(current).pathname.split('/')[2];
    const paths = performance.getEntriesByType('resource').map(e => new URL(e.name).pathname);
    const have = tiles.map(tile => paths.includes('/renditions/' + size + '/' + tile.dataset.path));
    const large = paths.filter(path => path.startsWith('/renditions/max/'));
    return {have, current, large};
  }
  """

  @tag Playwright.Test.use(viewport: %{width: 390, height: 844}, device_scale_factor: 3.0)
  test "a phone fetches the smaller picture and the next two at the same size", %{
    conn: conn,
    kb: kb
  } do
    {:ok, _} = Texttile.Settings.put(:image_max_edge, 2560)
    article = draft!(kb)
    [first | _] = pictures!(article)

    conn
    |> sign_in()
    |> open_editor(article.id)
    |> click(by_css("#tile-#{first.id}"))
    |> assert(contain_text(by_css("#lbCount"), "1 / 4"))
    |> assert_script(@fetched, fn result ->
      assert result["have"] == [true, true, true, false]
      assert result["current"] =~ "/renditions/1320/"
      assert result["large"] == []
    end)
    |> click(by_role(:button, name: "Next tile"))
    |> assert(contain_text(by_css("#lbCount"), "2 / 4"))
    |> assert_script(@fetched, fn result ->
      assert result["have"] == [true, true, true, true]
    end)
    |> click(by_role(:button, name: "Close"))
    |> refute_has(by_css("#lbRoot"))
  end

  @tag Playwright.Test.use(viewport: %{width: 1440, height: 900}, device_scale_factor: 2.0)
  test "a sharp desktop fetches the large picture", %{conn: conn, kb: kb} do
    {:ok, _} = Texttile.Settings.put(:image_max_edge, 2560)
    article = draft!(kb)
    [first | _] = pictures!(article)

    conn
    |> sign_in()
    |> open_editor(article.id)
    |> click(by_css("#tile-#{first.id}"))
    |> assert_script(@fetched, fn result ->
      assert result["have"] == [true, true, true, false]
      assert result["current"] =~ "/renditions/max/"
    end)
  end
end
