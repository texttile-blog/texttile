defmodule TexttileWeb.GalleryControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Articles
  alias Texttile.Gallery

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, article} = Articles.create_draft(user)
    %{article: article}
  end

  defp jpg_upload(name, opts \\ []) do
    %Plug.Upload{path: jpg_file(opts), filename: name, content_type: "image/jpeg"}
  end

  # Two black rectangles of one size are the same file byte for byte,
  # and an entry takes each picture once. Every file is its own picture
  # unless a test asks two of them to share a mark.
  defp jpg_file(opts) do
    path = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}.jpg")
    mark = Keyword.get_lazy(opts, :mark, fn -> "one-#{System.unique_integer([:positive])}" end)
    {:ok, black} = Vix.Vips.Operation.black(20, 10)

    {:ok, image} =
      Vix.Vips.Image.mutate(black, fn mut ->
        Vix.Vips.MutableImage.set(mut, "exif-ifd0-ImageDescription", :gchararray, mark)
      end)

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end

  test "puts the picture into the text's gallery", %{conn: conn, article: article} do
    conn = post(conn, ~p"/admin/texts/#{article.id}/gallery", %{"file" => jpg_upload("Pier.jpg")})

    assert %{"id" => id} = json_response(conn, 200)
    assert [%{id: ^id, filename: "Pier.jpg"}] = Gallery.list(article.id)
  end

  test "puts a video into the gallery and in line for the conversion", %{
    conn: conn,
    article: article
  } do
    upload = %Plug.Upload{
      path: Texttile.VideoFixtures.video_file(320, 240),
      filename: "Harbour.mov",
      content_type: "video/quicktime"
    }

    conn = post(conn, ~p"/admin/texts/#{article.id}/gallery", %{"file" => upload})

    assert %{"id" => id} = json_response(conn, 200)
    assert [%{id: ^id, path: path}] = Gallery.list(article.id)
    assert Texttile.Videos.get(path).state == "queued"
  end

  test "a file that is no image is refused", %{conn: conn, article: article} do
    path = Path.join(System.tmp_dir!(), "no-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "words")
    upload = %Plug.Upload{path: path, filename: "no.jpg", content_type: "image/jpeg"}

    conn = post(conn, ~p"/admin/texts/#{article.id}/gallery", %{"file" => upload})

    assert %{"error" => _} = json_response(conn, 422)
    assert Gallery.list(article.id) == []
  end

  test "no file is a plain 400", %{conn: conn, article: article} do
    conn = post(conn, ~p"/admin/texts/#{article.id}/gallery", %{})
    assert json_response(conn, 400)
  end

  # An unknown entry and a signed-out caller answer the same on both
  # upload endpoints, which share a pipeline and one lookup. They are
  # proved once, in images_controller_test.exs.

  test "the same picture a second time is refused, and named", %{conn: conn, article: article} do
    post(conn, ~p"/admin/texts/#{article.id}/gallery", %{
      "file" => jpg_upload("Pier Lantern.jpg", mark: "the same one")
    })

    conn =
      post(conn, ~p"/admin/texts/#{article.id}/gallery", %{
        "file" => jpg_upload("again.jpg", mark: "the same one")
      })

    assert %{"error" => error, "of" => "Pier Lantern.jpg"} = json_response(conn, 409)
    assert error =~ "Pier Lantern.jpg"
    assert [_only_one] = Gallery.list(article.id)
  end
end
