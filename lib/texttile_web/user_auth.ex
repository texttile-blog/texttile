defmodule TexttileWeb.UserAuth do
  @moduledoc """
  Signs admins in and out, and guards the routes.

  The identity travels as a session token. `current_scope` carries the
  user and that token through plugs and LiveViews.

  The token rides in two cookies. The session cookie is the one every
  request reads, and it dies when the browser closes. The auth cookie
  outlives that: it holds the same token, signed, for as long as the
  session lasts, so closing the browser is not signing out. Two days,
  and fourteen when the box on the sign-in form is ticked.
  """

  use TexttileWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Texttile.Accounts
  alias Texttile.Accounts.Scope

  @auth_cookie "_texttile_auth"

  @doc "The cookie that carries the sign-in over a closed browser."
  def auth_cookie, do: @auth_cookie

  @doc """
  Opens a session for the user, writes both cookies and redirects to
  the admin area. `remember?` is the box on the sign-in form.
  """
  def log_in_user(conn, user, remember? \\ false) do
    token = Accounts.create_session(user, remember: remember?)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> put_auth_cookie(token, remember?)
    |> redirect(to: ~p"/admin")
  end

  defp put_auth_cookie(conn, token, remember?) do
    put_resp_cookie(conn, @auth_cookie, token,
      sign: true,
      max_age: Accounts.session_max_age(remember?),
      same_site: "Lax",
      http_only: true,
      secure: conn.scheme == :https
    )
  end

  @doc """
  Ends the current session only: the token behind this browser's cookie
  is dropped, other browsers stay signed in.
  """
  def log_out_user(conn) do
    if token = get_session(conn, :user_token) do
      Accounts.delete_session(token)
    end

    if live_socket_id = get_session(conn, :live_socket_id) do
      TexttileWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc """
  Ends every session of the user, in every browser, and lands on the
  sign-in screen. The open sockets of the other browsers are told to
  disconnect; without that they would sit on dead tokens until a reload.
  """
  def log_out_everywhere(conn) do
    if scope = conn.assigns[:current_scope] do
      sessions = Accounts.list_sessions(scope.user)
      :ok = Accounts.delete_all_sessions(scope.user)

      Enum.each(sessions, fn session ->
        TexttileWeb.Endpoint.broadcast(user_session_topic(session.token_hash), "disconnect", %{})
      end)
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc """
  Plug: resolves the session token into `conn.assigns.current_scope`.

  A browser that was closed and opened again brings only the auth
  cookie. A token from there is asked about first and written into the
  session only once it names a live session, so nothing behind this
  plug, the upload roof included, ever sees a token the server has
  ended. A token that names nothing is dropped where it was found.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    case get_session(conn, :user_token) do
      token when is_binary(token) -> from_session(conn, token)
      _ -> from_auth_cookie(conn)
    end
  end

  defp from_session(conn, token) do
    case Accounts.get_user_by_session_token(token) do
      nil -> conn |> forget_token() |> assign(:current_scope, nil)
      user -> assign(conn, :current_scope, Scope.for_user(user, token))
    end
  end

  defp from_auth_cookie(conn) do
    conn = fetch_cookies(conn, signed: [@auth_cookie])

    case conn.cookies[@auth_cookie] do
      token when is_binary(token) -> promote(conn, token)
      _ -> assign(conn, :current_scope, nil)
    end
  end

  defp promote(conn, token) do
    case Accounts.get_user_by_session_token(token) do
      nil ->
        conn |> forget_token() |> assign(:current_scope, nil)

      user ->
        conn
        |> put_token_in_session(token)
        |> assign(:current_scope, Scope.for_user(user, token))
    end
  end

  # A token that signs nobody in has no business staying in a browser.
  # Both places it can hide are emptied, so the next request carries
  # nothing and the endpoint's upload roof stops reading it as a
  # sign-in.
  defp forget_token(conn) do
    conn
    |> delete_session(:user_token)
    |> delete_session(:live_socket_id)
    |> delete_resp_cookie(@auth_cookie, same_site: "Lax", http_only: true)
  end

  @doc """
  Plug: only signed-in admins pass. Everybody else goes to the sign-in
  screen, which is also where a configured name creates its account.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope do
      conn
    else
      conn |> redirect(to: ~p"/login") |> halt()
    end
  end

  @doc "Plug: the sign-in family is pointless for somebody signed in."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns.current_scope do
      conn |> redirect(to: ~p"/admin") |> halt()
    else
      conn
    end
  end

  @doc """
  LiveView `on_mount`: resolves the scope from the session and halts
  towards the sign-in family when there is none.
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      with token when is_binary(token) <- session["user_token"],
           user when not is_nil(user) <- Accounts.get_user_by_session_token(token) do
        Scope.for_user(user, token)
      else
        _ -> nil
      end
    end)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(Accounts.session_fingerprint(token)))
  end

  @doc """
  The LiveView socket id of a session, used to force a disconnect. It is
  built from the stored hash of the token, which is the only name of a
  session that both a cookie and a row can arrive at.
  """
  def user_session_topic(token_hash),
    do: "users_sessions:#{Base.url_encode64(token_hash)}"

  # Both cookies go together: a session the server has ended must not
  # come back from the one that outlives the browser.
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> delete_resp_cookie(@auth_cookie, same_site: "Lax", http_only: true)
  end
end
