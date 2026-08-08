defmodule TexttileWeb.StatsController do
  @moduledoc """
  The one address the view counter answers at.

  A reader page reports itself here and hears nothing back: no body,
  no cookie, no session. The request carries the address of the page,
  the entry it shows and where the reader came from, and that is all
  it can carry - the browser has nothing else to tell.

  Every answer is the same 204, whether the view counted or not. A
  caller learns nothing about the filters from the outside, and a
  reader's page never waits on an answer it does not read.
  """
  use TexttileWeb, :controller

  alias Texttile.Stats

  def count(conn, params) do
    Stats.count(%{
      path: params["p"],
      article_id: entry_id(params["id"]),
      referrer: text(params["r"]),
      ip: TexttileWeb.ClientIP.of(conn),
      user_agent: header(conn, "user-agent"),
      prefetch?: prefetch?(conn)
    })

    send_resp(conn, :no_content, "")
  end

  # The page writes its own entry id into the beacon. A caller can
  # write another one, so the counter checks it against the published
  # entries; anything else counts as a plain address.
  #
  # A number no row can wear is thrown away here and not asked about:
  # the database binds an id as a machine integer, and one digit too
  # many raises instead of answering "no such entry".
  @id_max 9_223_372_036_854_775_807

  defp entry_id(id) when is_integer(id) and id > 0 and id <= @id_max, do: id

  defp entry_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> entry_id(id)
      _ -> nil
    end
  end

  defp entry_id(_id), do: nil

  # A page the browser fetched before anybody clicked was read by
  # nobody. Chrome says so in Sec-Purpose, Firefox in X-Moz.
  defp prefetch?(conn) do
    String.contains?(header(conn, "sec-purpose"), "prefetch") or
      header(conn, "x-moz") in ["prefetch", "prerender"] or
      header(conn, "purpose") == "prefetch"
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> ""
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil
end
