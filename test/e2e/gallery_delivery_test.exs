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

  @fetched """
  (wanted) => new Promise(resolve => {
    const tiles = [...document.querySelectorAll('#tileServer [data-id]')];
    const started = Date.now();
    const check = () => {
      const img = document.querySelector('#lbImg img');
      const current = img?.currentSrc;
      const size = current && new URL(current).pathname.split('/')[2];
      const paths = performance.getEntriesByType('resource').map(e => new URL(e.name).pathname);
      const have = tiles.map(tile => paths.includes('/renditions/' + size + '/' + tile.dataset.path));
      const large = paths.filter(path => path.startsWith('/renditions/max/'));
      if (wanted.every(i => have[i]) || Date.now() - started > 4000) resolve({have, current, large});
      else setTimeout(check, 25);
    };
    check();
  })
  """

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}, device_scale_factor: 3.0]
  test "a phone fetches the smaller picture and the next two at the same size", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb)
    [first | _] = pictures!(article)

    conn
    |> sign_in()
    |> open_editor(article.id)
    |> click("#tile-#{first.id}")
    |> assert_has("#lbCount", text: "1 / 4")
    |> evaluate(@fetched, [arg: [0, 1, 2], is_function: true], fn result ->
      assert result["have"] == [true, true, true, false]
      assert result["current"] =~ "/renditions/1320/"
      assert result["large"] == []
    end)
    |> click_button("Next tile")
    |> assert_has("#lbCount", text: "2 / 4")
    |> evaluate(@fetched, [arg: [3], is_function: true], fn result ->
      assert result["have"] == [true, true, true, true]
    end)
    |> click_button("Close")
    |> refute_has("#lbRoot")
  end

  @tag browser_context_opts: [viewport: %{width: 1440, height: 900}, device_scale_factor: 2.0]
  test "a sharp desktop fetches the large picture", %{conn: conn, kb: kb} do
    article = draft!(kb)
    [first | _] = pictures!(article)

    conn
    |> sign_in()
    |> open_editor(article.id)
    |> click("#tile-#{first.id}")
    |> evaluate(@fetched, [arg: [0, 1, 2], is_function: true], fn result ->
      assert result["have"] == [true, true, true, false]
      assert result["current"] =~ "/renditions/max/"
    end)
  end
end
