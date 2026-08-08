defmodule TexttileWeb.GalleryControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads

  setup :register_and_log_in_user

  setup %{user: user} do
    File.rm_rf!(Uploads.root())
    {:ok, article} = Articles.create_draft(user)
    %{article: article}
  end

  defp jpg_upload(name) do
    path = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}.jpg")
    {:ok, black} = Vix.Vips.Operation.black(20, 10)
    :ok = Vix.Vips.Image.write_to_file(black, path)
    %Plug.Upload{path: path, filename: name, content_type: "image/jpeg"}
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

  test "an unknown text is a 404", %{conn: conn} do
    assert_error_sent 404, fn ->
      post(conn, ~p"/admin/texts/999999/gallery", %{"file" => jpg_upload("a.jpg")})
    end
  end

  test "signed out, the endpoint answers with a redirect to sign-in", %{article: article} do
    conn = post(build_conn(), ~p"/admin/texts/#{article.id}/gallery", %{})
    assert redirected_to(conn) == ~p"/login"
  end
end
