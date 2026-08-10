defmodule TexttileWeb.ImagesControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Articles
  alias Texttile.Uploads

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, article} = Articles.create_draft(user)
    %{article: article}
  end

  defp png_upload(name, opts \\ []) do
    %Plug.Upload{path: png_file(opts), filename: name, content_type: "image/png"}
  end

  # Two black rectangles of one size are the same file byte for byte,
  # and an entry takes each picture once. Every file is its own picture
  # unless a test asks two of them to share a mark.
  defp png_file(opts) do
    path = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}.png")
    mark = Keyword.get_lazy(opts, :mark, fn -> "one-#{System.unique_integer([:positive])}" end)
    {:ok, black} = Vix.Vips.Operation.black(20, 10)

    {:ok, image} =
      Vix.Vips.Image.mutate(black, fn mut ->
        Vix.Vips.MutableImage.set(mut, "exif-ifd0-ImageDescription", :gchararray, mark)
      end)

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end

  test "stores the image and answers with its address", %{conn: conn, article: article} do
    conn =
      post(conn, ~p"/admin/texts/#{article.id}/images", %{"file" => png_upload("Pier Gull.png")})

    assert %{"url" => "/uploads/images/" <> stored} = json_response(conn, 200)
    assert stored =~ ~r/^pier-gull-\w+\.png$/
    assert File.exists?(Uploads.absolute("images/" <> stored))
  end

  test "stores a video and puts it in line for the conversion", %{conn: conn, article: article} do
    upload = %Plug.Upload{
      path: Texttile.VideoFixtures.video_file(320, 240),
      filename: "Harbour Morning.mov",
      content_type: "video/quicktime"
    }

    conn = post(conn, ~p"/admin/texts/#{article.id}/images", %{"file" => upload})

    assert %{"url" => "/uploads/videos/" <> stored} = json_response(conn, 200)
    assert stored =~ ~r/^harbour-morning-\w+\.mov$/
    assert File.exists?(Uploads.absolute("videos/" <> stored))
    assert Texttile.Videos.get("videos/" <> stored).state == "queued"
  end

  test "a file that is no image is refused", %{conn: conn, article: article} do
    path = Path.join(System.tmp_dir!(), "no-#{System.unique_integer([:positive])}.png")
    File.write!(path, "words")
    upload = %Plug.Upload{path: path, filename: "no.png", content_type: "image/png"}

    conn = post(conn, ~p"/admin/texts/#{article.id}/images", %{"file" => upload})
    assert %{"error" => _} = json_response(conn, 422)
  end

  test "the same picture a second time is refused, and named", %{conn: conn, article: article} do
    conn
    |> post(~p"/admin/texts/#{article.id}/images", %{
      "file" => png_upload("Pier Gull.png", mark: "the same one")
    })
    |> json_response(200)

    # the body has to hold it before it counts as this entry's picture
    {:ok, article} =
      Articles.update_text(article, %{body: "![gull](/uploads/images/#{stored_name(article)})"})

    conn =
      post(conn, ~p"/admin/texts/#{article.id}/images", %{
        "file" => png_upload("again.png", mark: "the same one")
      })

    assert %{"error" => error, "of" => of} = json_response(conn, 409)
    assert of =~ ~r/^pier-gull-\w+\.png$/
    assert error =~ of
  end

  test "a picture that stands in another entry may come in here", %{conn: conn, user: user} do
    {:ok, mine} = Articles.create_draft(user)
    {:ok, theirs} = Articles.create_draft(user)

    %{"url" => "/uploads/" <> stored} =
      conn
      |> post(~p"/admin/texts/#{mine.id}/images", %{
        "file" => png_upload("gull.png", mark: "the same one")
      })
      |> json_response(200)

    {:ok, _} = Articles.update_text(mine, %{body: "![gull](/uploads/#{stored})"})

    assert %{"url" => _} =
             conn
             |> post(~p"/admin/texts/#{theirs.id}/images", %{
               "file" => png_upload("gull.png", mark: "the same one")
             })
             |> json_response(200)
  end

  test "an unknown text is a 404", %{conn: conn} do
    assert_error_sent 404, fn ->
      post(conn, ~p"/admin/texts/999999/images", %{"file" => png_upload("a.png")})
    end
  end

  test "signed out, the endpoint answers with a redirect to sign-in", %{article: article} do
    conn = post(build_conn(), ~p"/admin/texts/#{article.id}/images", %{})
    assert redirected_to(conn) == ~p"/login"
  end

  # The one picture that is on disk for this entry, as the body would
  # write it.
  defp stored_name(_article) do
    Uploads.absolute("images") |> File.ls!() |> Enum.find(&String.starts_with?(&1, "pier-gull-"))
  end
end
