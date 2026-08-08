defmodule TexttileWeb.ClientIPTest do
  @moduledoc """
  Which address the parts that count callers see.
  """
  use TexttileWeb.ConnCase, async: false

  alias TexttileWeb.ClientIP

  setup do
    on_exit(fn -> Application.delete_env(:texttile, :client_ip_header) end)
    :ok
  end

  defp conn_with(header, value) do
    build_conn() |> Plug.Conn.put_req_header(header, value)
  end

  test "without a named header the socket address decides" do
    Application.delete_env(:texttile, :client_ip_header)

    assert ClientIP.of(conn_with("x-forwarded-for", "9.9.9.9")) == "127.0.0.1"
  end

  test "a named header the proxy sets carries the reader" do
    Application.put_env(:texttile, :client_ip_header, "fly-client-ip")

    assert ClientIP.of(conn_with("fly-client-ip", "203.0.113.9")) == "203.0.113.9"
  end

  test "of a list, the entry the proxy appended is the reader" do
    Application.put_env(:texttile, :client_ip_header, "x-forwarded-for")

    # The spammer wrote the first entry themselves and the proxy wrote
    # theirs behind it. Reading the first would hand them a fresh
    # bucket per request.
    conn = conn_with("x-forwarded-for", "1.1.1.1, 203.0.113.9")

    assert ClientIP.of(conn) == "203.0.113.9"
  end

  test "an empty header falls back to the socket address" do
    Application.put_env(:texttile, :client_ip_header, "x-forwarded-for")

    assert ClientIP.of(conn_with("x-forwarded-for", "  ")) == "127.0.0.1"
    assert ClientIP.of(build_conn()) == "127.0.0.1"
  end
end
