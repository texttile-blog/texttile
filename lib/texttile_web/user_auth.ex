defmodule TexttileWeb.UserAuth do
  @moduledoc """
  Signs admins in and out, and guards the routes.

  The identity travels as a session token in the cookie. `current_scope`
  carries the user and that token through plugs and LiveViews.
  """

  use TexttileWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Texttile.Accounts
  alias Texttile.Accounts.Scope

  @doc """
  Opens a session for the user, renews the cookie and redirects to the
  desk.
  """
  def log_in_user(conn, user) do
    token = Accounts.create_session(user)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> redirect(to: ~p"/admin")
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
        TexttileWeb.Endpoint.broadcast(user_session_topic(session.token), "disconnect", %{})
      end)
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc "Plug: resolves the session token into `conn.assigns.current_scope`."
  def fetch_current_scope_for_user(conn, _opts) do
    with token when is_binary(token) <- get_session(conn, :user_token),
         user when not is_nil(user) <- Accounts.get_user_by_session_token(token) do
      assign(conn, :current_scope, Scope.for_user(user, token))
    else
      _ -> assign(conn, :current_scope, nil)
    end
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
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc "The LiveView socket id of a session, used to force a disconnect."
  def user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
