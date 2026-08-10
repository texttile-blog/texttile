defmodule TexttileWeb.BackupGate do
  @moduledoc """
  Who gets to the backup API, and what everybody else is told.

  Three questions in order, and each has its own answer:

    * Has this caller knocked too often this minute? Then 429, and
      nothing further is asked. This stands first so that a scanner
      running at a switched-off installation is throttled like
      anybody else, instead of writing a log line per knock forever.
    * Is this installation serving backups at all, and to this
      address? If not, the endpoints are not there. A scanner gets
      the same 404 as for any address nobody wrote a route for, and
      learns nothing about what this server can do. A forbidden says
      "there is something here"; a not-found says nothing.
    * Does the word they carry open it? If not, 401.

  The word travels in the `Authorization` header and nowhere else. A
  token in the address line is written into the access log of this
  server, of every proxy in front of it, and into the shell history
  of whoever tried it by hand.

  Every knock is logged, granted or not. A backup that stopped
  running and a stranger trying words both show there first.
  """

  import Plug.Conn

  require Logger

  alias Texttile.Backup
  alias Texttile.RateLimiter
  alias TexttileWeb.ClientIP

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = ClientIP.of(conn)

    cond do
      not RateLimiter.allow?(ip, Backup.limiter()) ->
        refuse(conn, ip, 429, "too many requests", "too many requests this minute")

      not Backup.enabled?() ->
        refuse(conn, ip, 404, "not found", "the backup API is switched off")

      not Backup.allowed_ip?(ip) ->
        refuse(conn, ip, 404, "not found", "the address is not on the allowlist")

      not Backup.valid_token?(presented(conn)) ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> refuse(ip, 401, "unauthorized", "the token does not open it")

      true ->
        Logger.info("backup: #{conn.request_path} served to #{ip}")
        assign(conn, :backup_ip, ip)
    end
  end

  defp refuse(conn, ip, status, body, why) do
    Logger.warning("backup: #{conn.request_path} refused for #{ip}, #{why}")

    conn
    |> send_resp(status, body)
    |> halt()
  end

  # `Bearer <token>`, with a scheme a client may write in any case.
  defp presented(conn) do
    with [line] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(line, " ", parts: 2),
         "bearer" <- String.downcase(scheme) do
      String.trim(token)
    else
      _no_word -> nil
    end
  end
end
