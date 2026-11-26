defmodule TexttileWeb.E2E.VideoFlowTest do
  @moduledoc """
  The whole way of a video: an admin picks one in the editor, ffmpeg
  converts it in the background, the tile wears its poster, and the
  published text plays it.
  """
  use TexttileWeb.E2E

  import Ecto.Query, only: [from: 2]
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads
  alias Texttile.Videos

  setup do
    # The queue stays out of the test environment; this test wants the
    # real one, under its own sandbox owner.
    start_supervised!(Texttile.Videos.Queue)
    :ok
  end

  defp picture_file do
    path = Path.join(System.tmp_dir!(), "tile-#{System.unique_integer([:positive])}.jpg")
    {:ok, black} = Vix.Vips.Operation.black(40, 30)
    :ok = Vix.Vips.Image.write_to_file(black, path)
    path
  end

  # ffmpeg is slower than a broadcast: this waits for a real conversion.
  @conversion_ms 20_000

  defp wait_until(fun), do: eventually(fun, @conversion_ms)

  test "a picked video becomes a tile, converts, and plays for the reader", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb)

    session =
      conn
      |> sign_in()
      |> open_editor(article.id)
      |> assert(contain_text(by_css("#tileCount"), "0 tiles"))
      |> set_input_files(by_label("Add pictures and videos to the gallery"), video_file(640, 480))
      |> assert_has(by_css("#tileServer [data-id]"), timeout: 30_000)

    [image] = Gallery.list(article.id)
    assert image.path =~ ~r"^videos/"

    # the admin area says what is happening while ffmpeg works, and stops
    # saying it once the poster is there
    video =
      wait_until(fn ->
        match?(%{state: "done"}, Videos.get(image.path)) && Videos.get(image.path)
      end)

    session
    |> assert_has(by_css("#tile-#{image.id}[data-video]"), timeout: 10_000)
    |> refute_has(by_css("#tile-#{image.id}.tile-waiting"))

    {:ok, article} = Articles.publish(Articles.get_article!(article.id), kb)

    conn
    |> open_page(Articles.public_path(article))
    |> assert_has(by_css("#gal a[data-video='/uploads/#{video.mp4_path}']"))
  end

  test "the admin lightbox never lands on a tile that has nothing to show", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb)
    {:ok, _picture} = Gallery.add_file(article, picture_file(), "Pier.jpg")
    {:ok, waiting} = Gallery.add_file(article, video_file(320, 240), "Harbour.mov")

    # back to where a long conversion keeps a video: no poster, no
    # film, and a tile with nothing to show
    wait_until(fn -> Videos.get(waiting.path).state == "done" end)

    Texttile.Repo.update_all(from(v in Texttile.Videos.Video, where: v.path == ^waiting.path),
      set: [state: "queued", mp4_path: nil, poster_path: nil]
    )

    assert Videos.get(waiting.path).state == "queued"

    conn
    |> sign_in()
    |> open_editor(article.id)
    |> assert_has(by_css("#tile-#{waiting.id}.tile-waiting"))
    |> click(by_css("#tileServer [data-id]:not(.tile-waiting)"))
    |> assert_has(by_css("#lbRoot"))
    |> assert(contain_text(by_css("#lbCount"), "1 / 1"))
    |> press(by_css("#lbRoot"), "ArrowRight")
    |> assert(contain_text(by_css("#lbCount"), "1 / 1"))
    |> refute_has(by_css("#lbState") |> filter(has_text: "could not be shown"))
  end

  # where the film stands in the admin lightbox, and whether it knows
  # its size yet
  @film_box """
  () => {
    const film = document.querySelector('#lbImg video');
    const box = r => ({left: r.left, right: r.right, top: r.top, bottom: r.bottom});
    return {sized: film.readyState >= 1,
            film: box(film.getBoundingClientRect()),
            room: box(document.querySelector('#lbImg').getBoundingClientRect())};
  }
  """

  @tag Playwright.Test.use(viewport: %{width: 1440, height: 900})
  test "the admin lightbox fits a film whole and centers it", %{conn: conn, kb: kb} do
    article = draft!(kb)
    {:ok, portrait} = Gallery.add_file(article, video_file(720, 1280), "Gorge.mp4")
    {:ok, landscape} = Gallery.add_file(article, video_file(1280, 720), "Village.mp4")
    wait_until(fn -> Enum.all?([portrait, landscape], &(Videos.get(&1.path).state == "done")) end)

    session = conn |> sign_in() |> open_editor(article.id)

    for tile <- [portrait, landscape] do
      session
      |> click(by_css("#tile-#{tile.id}"))
      |> assert_has(by_css("#lbImg video"))
      |> assert_script(@film_box, fn %{"sized" => sized, "film" => film, "room" => room} ->
        assert sized
        assert film["top"] >= room["top"] - 1 and film["bottom"] <= room["bottom"] + 1
        assert film["left"] >= room["left"] - 1 and film["right"] <= room["right"] + 1
        center = fn box -> (box["left"] + box["right"]) / 2 end
        assert_in_delta center.(film), center.(room), 1
      end)
      |> click(by_role(:button, name: "Close"))
      |> refute_has(by_css("#lbRoot"))
    end
  end

  test "a video dropped into the words plays where it stands", %{conn: conn, kb: kb} do
    article = draft!(kb)
    {:ok, relative} = Uploads.put_body_video(video_file(640, 480), "Harbour.mov")
    Videos.queue(relative)

    {:ok, article} =
      Articles.update_text(article, %{body: "Look:\n\n![Harbour](/uploads/#{relative})"})

    video =
      wait_until(fn -> match?(%{state: "done"}, Videos.get(relative)) && Videos.get(relative) end)

    # the writing surface draws the reference as its poster
    conn
    |> sign_in()
    |> open_editor(article.id)
    |> assert_has(by_css(".cm-mdvid[style*='#{video.poster_path}']"), timeout: 10_000)

    {:ok, article} = Articles.publish(article, kb)

    conn
    |> open_page(Articles.public_path(article))
    |> assert_has(by_css("video.bodyvid[src='/uploads/#{video.mp4_path}']"))
  end

  test "the thumbnails in the words open full size and page through each other",
       %{conn: conn, kb: kb} do
    article = draft!(kb)
    {:ok, picture} = Uploads.put_body_image(picture_file(), "Pier.jpg")
    {:ok, relative} = Uploads.put_body_video(video_file(640, 480), "Harbour.mov")
    Videos.queue(relative)

    {:ok, article} =
      Articles.update_text(article, %{
        # never on the first line: the caret starts there, and the line
        # the caret is on shows its markdown raw
        body: "Look:\n\n![Pier](/uploads/#{picture})\n\nand\n\n![Harbour](/uploads/#{relative})"
      })

    video =
      wait_until(fn -> match?(%{state: "done"}, Videos.get(relative)) && Videos.get(relative) end)

    session =
      conn
      |> sign_in()
      |> open_editor(article.id)
      |> assert_has(by_css(".cm-mdvid[style*='#{video.poster_path}']"), timeout: 10_000)

    # the picture opens at its reader size, and the caption is its alt
    session
    |> click(by_css(".cm-mdimg[data-url='/uploads/#{picture}']"))
    |> assert_has(by_css("#mediaLb"))
    |> assert(contain_text(by_css("#mlCount"), "1 / 2"))
    |> assert_has(by_css("#mlArt img[src='/renditions/max/#{picture}']"))
    |> assert(contain_text(by_css("#mlCap"), "Pier"))

    # the arrow key pages to the film, which stands there ready to play
    session
    |> press(by_css("#mediaLb"), "ArrowRight")
    |> assert(contain_text(by_css("#mlCount"), "2 / 2"))
    |> assert_has(by_css("#mlArt video[src='/uploads/#{video.mp4_path}']"))

    session
    |> press(by_css("#mediaLb"), "Escape")
    |> refute_has(by_css("#mediaLb"))
  end
end
