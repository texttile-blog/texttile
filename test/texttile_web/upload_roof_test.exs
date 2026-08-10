defmodule TexttileWeb.UploadRoofTest do
  @moduledoc """
  The two body roofs of the endpoint (see `TexttileWeb.Endpoint`).

  The small one is for everybody and never moves: 52 MB, before half a
  gigabyte has arrived. The big one belongs to the admin area's upload
  addresses and to a signed-in session, and it is Settings > Storage >
  Biggest upload, so what the settings screen promises and what the
  parser does are the same number.
  """
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Settings

  @boundary "----texttile"

  # Just past the 52 MB roof everybody has, far below the 512 MB the
  # admin area gets by default.
  defp oversize_body do
    body(53_000_000)
  end

  defp body(bytes) do
    "--#{@boundary}\r\n" <>
      ~s(Content-Disposition: form-data; name="file"; filename="big.mp4"\r\n) <>
      "Content-Type: video/mp4\r\n\r\n" <>
      String.duplicate("x", bytes) <>
      "\r\n--#{@boundary}--\r\n"
  end

  defp send_body(conn, payload \\ nil) do
    conn
    |> put_req_header("content-type", "multipart/form-data; boundary=#{@boundary}")
    |> post(~p"/admin/images", payload || oversize_body())
  end

  defp signed_in, do: Plug.Test.init_test_session(build_conn(), user_token: "not a live session")

  test "a stranger is refused at the roof everybody has" do
    assert_error_sent 413, fn -> send_body(build_conn()) end
  end

  test "a signed-in session gets the big roof, and the router does the rest" do
    conn = send_body(signed_in())

    # the body was read, so the roof was the big one; the token names no
    # session, so the admin area sends the caller to the sign-in screen
    assert redirected_to(conn) == ~p"/login"
  end

  test "the big roof is the setting, and a new value holds at once" do
    {:ok, _} = Settings.put(:max_upload_mb, 10)

    # the same body the default roof let through
    assert_error_sent 413, fn -> send_body(signed_in()) end

    {:ok, _} = Settings.put(:max_upload_mb, 512)
    assert redirected_to(send_body(signed_in())) == ~p"/login"
  end

  test "the setting does not raise the roof a stranger meets" do
    {:ok, _} = Settings.put(:max_upload_mb, 2048)

    assert_error_sent 413, fn -> send_body(build_conn()) end
  end

  # A browser that was closed and opened again brings only the auth
  # cookie, and its first request may well be the upload a restored tab
  # was still holding. The roof stands before the router, so it reads
  # that cookie itself.
  test "a browser that carries only the auth cookie gets the big roof" do
    user = Texttile.AccountsFixtures.user_fixture()

    auth =
      build_conn()
      |> post(~p"/login", %{
        "user" => %{
          "username" => user.username,
          "password" => Texttile.AccountsFixtures.valid_password()
        }
      })
      |> Map.fetch!(:resp_cookies)
      |> Map.fetch!(TexttileWeb.UserAuth.auth_cookie())
      |> Map.fetch!(:value)

    # the session behind it ends, so the body is read and the router
    # turns the caller away, exactly as with a session cookie
    :ok = Texttile.Accounts.delete_all_sessions(user)

    conn =
      build_conn()
      |> Plug.Test.put_req_cookie(TexttileWeb.UserAuth.auth_cookie(), auth)
      |> send_body()

    assert redirected_to(conn) == ~p"/login"
  end
end
