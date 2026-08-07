defmodule TexttileWeb.SiteGate do
  @moduledoc """
  The site password, on the reader's way in.

  The password is a shared access word, one for the whole blog, stored
  in plain text (it goes into notification mails and gets passed
  around). It guards the blog or nothing: no text carries a switch of
  its own. This plug answers one question per request - may this reader
  in? - into `conn.assigns.site_unlocked`, and while the blog is
  protected it walks a locked reader to the gate at `/unlock`, with the
  way back in `?to=`.

  Unlocked is: a signed-in admin, a reader who entered the password this
  session, or a blank stored password (nothing to ask for).
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

  @doc "May this reader read the blog?"
  def unlocked?(conn) do
    conn.assigns[:current_scope] != nil or
      get_session(conn, :site_unlocked) == true or
      Settings.get(:site_password) == ""
  end

  @doc """
  Marks the session: this reader entered the password. The session id
  is renewed, so the mark never lands on an id somebody else planted.
  """
  def unlock(conn) do
    conn
    |> configure_session(renew: true)
    |> put_session(:site_unlocked, true)
  end

  # What Phoenix refuses in a local redirect; anything carrying these
  # falls back to the front page instead of raising there.
  @unsafe_chars ["\\", "/%09", "/\t"]

  @doc """
  Where the gate sends the reader afterwards: only a clean path on this
  site. Anything absolute, protocol-relative, absent or carrying an
  unsafe character falls back to the front page.
  """
  def safe_return(to) do
    case to do
      "/" <> _ = path ->
        if String.starts_with?(path, "//") or String.contains?(path, @unsafe_chars) do
          "/"
        else
          path
        end

      _ ->
        "/"
    end
  end

  # Only a page a reader can open again. A POST address answers nothing
  # on a GET, so a form that ran into the gate sends its reader to the
  # front page instead of into a dead end.
  defp way_back(%Plug.Conn{method: "GET"} = conn) do
    case conn.query_string do
      "" -> conn.request_path
      query -> conn.request_path <> "?" <> query
    end
  end

  defp way_back(_conn), do: "/"
end
