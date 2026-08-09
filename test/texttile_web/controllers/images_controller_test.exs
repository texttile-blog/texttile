defmodule TexttileWeb.ImagesControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Uploads

  setup :register_and_log_in_user

  defp png_upload(name) do
    path = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}.png")
    {:ok, black} = Vix.Vips.Operation.black(20, 10)
    :ok = Vix.Vips.Image.write_to_file(black, path)
    %Plug.Upload{path: path, filename: name, content_type: "image/png"}
  end

  test "stores the image and answers with its address", %{conn: conn} do
    conn = post(conn, ~p"/admin/images", %{"file" => png_upload("Pier Gull.png")})

    assert %{"url" => "/uploads/images/" <> stored} = json_response(conn, 200)
    assert stored =~ ~r/^pier-gull-\w+\.png$/
    assert File.exists?(Uploads.absolute("images/" <> stored))
  end

  test "stores a video and puts it in line for the conversion", %{conn: conn} do
    upload = %Plug.Upload{
      path: Texttile.VideoFixtures.video_file(320, 240),
      filename: "Harbour Morning.mov",
      content_type: "video/quicktime"
    }

    conn = post(conn, ~p"/admin/images", %{"file" => upload})

    assert %{"url" => "/uploads/videos/" <> stored} = json_response(conn, 200)
    assert stored =~ ~r/^harbour-morning-\w+\.mov$/
    assert File.exists?(Uploads.absolute("videos/" <> stored))
    assert Texttile.Videos.get("videos/" <> stored).state == "queued"
  end

  test "a file that is no image is refused", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "no-#{System.unique_integer([:positive])}.png")
    File.write!(path, "words")
    upload = %Plug.Upload{path: path, filename: "no.png", content_type: "image/png"}

    conn = post(conn, ~p"/admin/images", %{"file" => upload})
    assert %{"error" => _} = json_response(conn, 422)
  end

  test "signed out, the endpoint answers with a redirect to sign-in" do
    conn = post(build_conn(), ~p"/admin/images", %{})
    assert redirected_to(conn) == ~p"/login"
  end
end
