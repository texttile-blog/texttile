defmodule TexttileWeb.UploadRoofTest do
  @moduledoc """
  The two body roofs of the endpoint (see `TexttileWeb.Endpoint`). The
  big one belongs to the desk's upload addresses and to a signed-in
  session; a stranger is turned away at 52 MB, before half a gigabyte
  has arrived.
  """
  use TexttileWeb.ConnCase, async: false

  @boundary "----texttile"

  # Just past the 52 MB roof everybody has, far below the 520 MB the
  # desk gets.
  defp oversize_body do
    "--#{@boundary}\r\n" <>
      ~s(Content-Disposition: form-data; name="file"; filename="big.mp4"\r\n) <>
      "Content-Type: video/mp4\r\n\r\n" <>
      String.duplicate("x", 53_000_000) <>
      "\r\n--#{@boundary}--\r\n"
  end

  defp send_body(conn) do
    conn
    |> put_req_header("content-type", "multipart/form-data; boundary=#{@boundary}")
    |> post(~p"/admin/images", oversize_body())
  end

  test "a stranger is refused at the roof everybody has" do
    assert_error_sent 413, fn -> send_body(build_conn()) end
  end

  test "a signed-in session gets the big roof, and the router does the rest" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(user_token: "not a live session")
      |> send_body()

    # the body was read, so the roof was the big one; the token names no
    # session, so the desk sends the caller to the sign-in screen
    assert redirected_to(conn) == ~p"/login"
  end
end
