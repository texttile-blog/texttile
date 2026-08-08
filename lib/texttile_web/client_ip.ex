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

  Of a header that carries a list, the last entry is the answer. A
  proxy that appends writes there, and everything before it is what
  the caller sent: `X-Forwarded-For: 1.2.3.4` from a spammer, with
  their real address behind it. A header the proxy sets rather than
  appends carries one entry, so the last is the only one.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @doc "The address of the caller behind this connection."
  def of(conn) do
    header = Application.get_env(:texttile, :client_ip_header)

    with name when is_binary(name) <- header,
         [value | _] <- get_req_header(conn, name),
         nearest when nearest != "" <-
           value |> String.split(",") |> List.last() |> String.trim() do
      nearest
    else
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
