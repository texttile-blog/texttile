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

  describe "a file that arrives in pieces" do
    test "welds together and lands as one picture", %{conn: conn, article: article} do
      bytes = File.read!(jpg_file(mark: "the pieces one"))
      {first, rest} = String.split_at(bytes, div(byte_size(bytes), 2))

      conn = send_piece(conn, article, index: 0, parts: 2, size: byte_size(bytes), body: first)
      assert conn.status == 204

      conn = send_piece(conn, article, index: 1, parts: 2, size: byte_size(bytes), body: rest)
      assert %{"id" => id} = json_response(conn, 200)
      assert [%{id: ^id, filename: "Pier.jpg"}] = Gallery.list(article.id)
    end

    test "pieces that do not add up to the announced size are a restart", %{
      conn: conn,
      article: article
    } do
      bytes = File.read!(jpg_file([]))
      size = byte_size(bytes)

      conn = send_piece(conn, article, index: 0, parts: 2, size: size + 5, body: bytes)
      assert conn.status == 204

      conn = send_piece(conn, article, index: 1, parts: 2, size: size + 5, body: "x")
      assert %{"error" => error, "restart" => true} = json_response(conn, 409)
      assert Gallery.list(article.id) == []
    end

    test "a piece without the ones before it is a restart", %{conn: conn, article: article} do
      conn =
        send_piece(conn, article,
          index: 1,
          parts: 2,
          size: 100,
          body: "half a picture is no picture"
        )

      assert %{"restart" => true} = json_response(conn, 409)
      assert Gallery.list(article.id) == []
    end

    test "a file over the roof is turned away before its pieces travel", %{
      conn: conn,
      article: article
    } do
      conn =
        send_piece(conn, article,
          index: 0,
          parts: 1,
          size: 600 * 1024 * 1024,
          body: "nothing to read"
        )

      assert %{"error" => _} = json_response(conn, 413)
      assert Gallery.list(article.id) == []
    end

    test "pieces that name themselves badly are a 400", %{conn: conn, article: article} do
      conn =
        send_piece(conn, article, index: 0, parts: 1, size: 10, body: "x", upload: "has-dash")

      assert json_response(conn, 400)
    end
  end

  defp send_piece(conn, article, opts) do
    query =
      URI.encode_query(
        upload: Keyword.get(opts, :upload, "aaaaaaaaaaaaaaaa"),
        index: Keyword.fetch!(opts, :index),
        parts: Keyword.fetch!(opts, :parts),
        size: Keyword.fetch!(opts, :size),
        name: Keyword.get(opts, :name, "Pier.jpg")
      )

    conn
    |> ensure_recycled()
    |> put_req_header("content-type", "application/octet-stream")
    |> post("/admin/texts/#{article.id}/gallery/chunks?" <> query, Keyword.get(opts, :body, ""))
  end
end
