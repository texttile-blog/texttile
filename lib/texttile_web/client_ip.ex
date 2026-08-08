defmodule TexttileWeb.ClientIP do
  @moduledoc """
  The caller's address, as the parts that count callers know it.

  The socket address is the one nobody can choose, so it is the
  answer everywhere. A forwarding header is read only where the
  deployment names one (`CLIENT_IP_HEADER`, see the README): behind a
  proxy the socket address is the proxy's, and every reader would
  share one bucket. Anywhere else the header is just a line the caller
  wrote, and trusting it hands every spammer a fresh bucket per
  request.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @doc "The address of the caller behind this connection."
  def of(conn) do
    header = Application.get_env(:texttile, :client_ip_header)

    with name when is_binary(name) <- header,
         [value | _] <- get_req_header(conn, name),
         first when first != "" <- value |> String.split(",") |> hd() |> String.trim() do
      first
    else
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
