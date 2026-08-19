defmodule TexttileWeb.LinkController do
  @moduledoc """
  The mailed set-a-password link, and the screen that asks for one.
  The invitation of a new admin and the password reset both end here:
  the owner picks a password, and only the owner.
  """
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias TexttileWeb.UserAuth

  def show(conn, %{"token" => token}) do
    case Accounts.verify_login_link(token) do
      {:ok, user} ->
        render(conn, :show,
          user: user,
          token: token,
          error: nil,
          invitation: Accounts.pending?(user)
        )

      :error ->
        render(conn, :dead)
    end
  end

  def create(conn, %{"token" => token} = params) do
    password = get_in(params, ["user", "password"]) || ""

    # The sessions to disconnect are read first: accepting the link
    # deletes their rows, and the open sockets behind them must go too.
    sessions =
      case Accounts.verify_login_link(token) do
        {:ok, user} -> Accounts.list_sessions(user)
        :error -> []
      end

    case Accounts.accept_login_link(token, password) do
      {:ok, user} ->
        Enum.each(
          sessions,
          &TexttileWeb.Endpoint.broadcast(
            UserAuth.user_session_topic(&1.token_hash),
            "disconnect",
            %{}
          )
        )

        UserAuth.log_in_user(conn, user)

      {:error, changeset} ->
        # The link was alive a moment ago; when a concurrent accept
        # spent it in between, say so instead of crashing.
        case Accounts.verify_login_link(token) do
          {:ok, user} ->
            render(conn, :show,
              user: user,
              token: token,
              error: first_error(changeset),
              invitation: Accounts.pending?(user)
            )

          :error ->
            render(conn, :dead)
        end

      :error ->
        render(conn, :dead)
    end
  end

  def forgot(conn, _params) do
    render(conn, :forgot, sent: false)
  end

  def send_link(conn, %{"user" => %{"email" => email}}) do
    # The mail goes out only when the address has an account with a
    # password, but the answer is the same either way: this screen never
    # says who is a member. An account that never had a password has
    # nothing to forget, and its invitation belongs to the people who
    # sent it: a fresh link replaces the pending one, so a stranger who
    # knows the address could otherwise kill the invitation in the
    # inbox it just reached, once a minute, for as long as it takes.
    # That link is sent again from Settings > Users.
    #
    # One mail per account per minute either way, so a stranger
    # hammering this form neither floods an inbox nor churns a link.
    # The site name in the mail comes from the endpoint config, never
    # from the request's Host header.
    case Accounts.get_user_by_email(email) do
      nil ->
        :ok

      user ->
        unless Accounts.pending?(user) or Accounts.link_recently_sent?(user) do
          Accounts.send_password_link(user,
            site: TexttileWeb.Endpoint.host(),
            link_url: &url(~p"/link/#{&1}")
          )
        end
    end

    render(conn, :forgot, sent: true)
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&TexttileWeb.CoreComponents.translate_error/1)
    |> Map.values()
    |> List.flatten()
    |> List.first()
  end
end
