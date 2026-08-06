defmodule TexttileWeb.SiteGate do
  @moduledoc """
  The site password, on the reader's way in.

  The password is a shared access word, one for the whole blog, stored
  in plain text (it goes into notification mails and gets passed
  around). This plug answers one question per request - may this reader
  see protected texts? - into `conn.assigns.site_unlocked`, and when the
  whole blog is protected it walks a locked reader to the gate at
  `/unlock`, with the way back in `?to=`.

  Unlocked is: a signed-in admin, a reader who entered the password this
  session, or a blank stored password (nothing to ask for). The
  per-text switch is judged where the text is served, with this same
  assign.
  """

  use TexttileWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Texttile.Settings

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = assign(conn, :site_unlocked, unlocked?(conn))

    if conn.assigns.site_unlocked or Settings.get(:site_visibility) == "public" do
      conn
    else
      conn |> redirect(to: ~p"/unlock?to=#{way_back(conn)}") |> halt()
    end
  end

  @doc "May this reader see protected texts?"
  def unlocked?(conn) do
    conn.assigns[:current_scope] != nil or
      get_session(conn, :site_unlocked) == true or
      Settings.get(:site_password) == ""
  end

  @doc "Marks the session: this reader entered the password."
  def unlock(conn), do: put_session(conn, :site_unlocked, true)

  @doc """
  Where the gate sends the reader afterwards: only a path on this site.
  Anything absolute, protocol-relative or absent falls back to the
  front page.
  """
  def safe_return(to) do
    case to do
      "/" <> _ = path -> if String.starts_with?(path, "//"), do: "/", else: path
      _ -> "/"
    end
  end

  defp way_back(conn) do
    case conn.query_string do
      "" -> conn.request_path
      query -> conn.request_path <> "?" <> query
    end
  end
end
