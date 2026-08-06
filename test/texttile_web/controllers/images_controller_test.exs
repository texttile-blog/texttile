defmodule TexttileWeb.ImagesControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Uploads

  setup :register_and_log_in_user

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  defp png_upload(name) do
    path = Path.join(System.tmp_dir!(), "up-#{System.unique_integer([:positive])}.png")
    {:ok, black} = Vix.Vips.Operation.black(20, 10)
    :ok = Vix.Vips.Image.write_to_file(black, path)
    %Plug.Upload{path: path, filename: name, content_type: "image/png"}
  end

  test "stores the image and answers with its address", %{conn: conn} do
    conn = post(conn, ~p"/edit/images", %{"file" => png_upload("Pier Gull.png")})

    assert %{"url" => "/uploads/images/" <> stored} = json_response(conn, 200)
    assert stored =~ ~r/^pier-gull-\w+\.png$/
    assert File.exists?(Uploads.absolute("images/" <> stored))
  end

  test "a file that is no image is refused", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "no-#{System.unique_integer([:positive])}.png")
    File.write!(path, "words")
    upload = %Plug.Upload{path: path, filename: "no.png", content_type: "image/png"}

    conn = post(conn, ~p"/edit/images", %{"file" => upload})
    assert %{"error" => _} = json_response(conn, 422)
  end

  test "signed out, the endpoint answers with a redirect to sign-in" do
    conn = post(build_conn(), ~p"/edit/images", %{})
    assert redirected_to(conn) == ~p"/login"
  end
end
