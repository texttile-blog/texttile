defmodule TexttileWeb.UploadRoofTest do
  @moduledoc """
  The three body roofs of the endpoint (see `TexttileWeb.Endpoint`).

  A stranger sends no files, so a stranger gets 1 MB. A signed-in
  session gets 52 MB anywhere, before half a gigabyte has arrived. The
  big one belongs to the admin area's upload addresses and to a
  signed-in session, and it is Settings > Storage > Upload size limit, so
  what the settings screen promises and what the parser does are the
  same number.
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
    |> post(~p"/admin/texts/1/images", payload || oversize_body())
  end

  defp signed_in, do: Plug.Test.init_test_session(build_conn(), user_token: "not a live session")

  test "a stranger is refused at the upload address" do
    assert_error_sent 413, fn -> send_body(build_conn()) end
  end

  # Nothing a stranger can reach takes a file, so 2 MB of multipart is
  # already more than any of it has a use for.
  test "a stranger is refused far below the roof a session has" do
    assert_error_sent 413, fn ->
      build_conn()
      |> put_req_header("content-type", "multipart/form-data; boundary=#{@boundary}")
      |> post(~p"/admin/texts", body(2_000_000))
    end
  end

  test "a signed-in session keeps 52 MB away from the upload addresses" do
    conn =
      signed_in()
      |> put_req_header("content-type", "multipart/form-data; boundary=#{@boundary}")
      |> post(~p"/admin/texts", body(2_000_000))

    # the body was read, so the roof was not the stranger's; no route
    # takes a POST here, which is the router's answer, one roof later
    assert conn.status == 404
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
          "email" => user.email,
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

  # Plug.Parsers.MULTIPART defaults to 1 MB reads, while
  # Plug.Conn.read_part_headers/2 defaults to a 5 s timeout. Over
  # Bandit's blocking socket recv, any upload whose first megabyte takes
  # more than five seconds used to die with 400 (and a reverse proxy
  # turned the early close into 502).
  test "a slow upload whose first megabyte takes more than five seconds still reaches the router" do
    user = Texttile.AccountsFixtures.user_fixture()

    auth =
      build_conn()
      |> post(~p"/login", %{
        "user" => %{
          "email" => user.email,
          "password" => Texttile.AccountsFixtures.valid_password()
        }
      })
      |> Map.fetch!(:resp_cookies)
      |> Map.fetch!(TexttileWeb.UserAuth.auth_cookie())
      |> Map.fetch!(:value)

    payload = body(1_200_000)
    <<first_chunk::binary-size(32_000), rest::binary>> = payload
    port = Application.fetch_env!(:texttile, TexttileWeb.Endpoint)[:http][:port]

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)

    headers =
      "POST /admin/texts/1/gallery HTTP/1.1\r\n" <>
        "Host: localhost:#{port}\r\n" <>
        "Cookie: #{TexttileWeb.UserAuth.auth_cookie()}=#{auth}\r\n" <>
        "Content-Type: multipart/form-data; boundary=#{@boundary}\r\n" <>
        "Content-Length: #{byte_size(payload)}\r\n" <>
        "Connection: close\r\n\r\n"

    :ok = :gen_tcp.send(socket, headers)
    :ok = :gen_tcp.send(socket, first_chunk)
    Process.sleep(5_300)
    :ok = :gen_tcp.send(socket, rest)

    {:ok, response} = :gen_tcp.recv(socket, 0, 10_000)

    # The parser read the entire slow body and handed off to the router,
    # where CSRF rejects the bare request with 403 rather than 400.
    assert response =~ "HTTP/1.1 403"
  end
end
