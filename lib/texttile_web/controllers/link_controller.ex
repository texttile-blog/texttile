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
        render(conn, :show, user: user, token: token, error: nil)

      :error ->
        render(conn, :dead)
    end
  end

  def create(conn, %{"token" => token} = params) do
    password = get_in(params, ["user", "password"]) || ""

    case Accounts.accept_login_link(token, password) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, changeset} ->
        {:ok, user} = Accounts.verify_login_link(token)
        render(conn, :show, user: user, token: token, error: first_error(changeset))

      :error ->
        render(conn, :dead)
    end
  end

  def forgot(conn, _params) do
    render(conn, :forgot, sent: false)
  end

  def send_link(conn, %{"user" => %{"email" => email}}) do
    # The mail goes out only when the address has an account, but the
    # answer is the same either way: this screen never says who is a
    # member.
    case Accounts.get_user_by_email(email) do
      nil ->
        :ok

      user ->
        Accounts.send_password_link(user,
          site: conn.host,
          link_url: &url(~p"/link/#{&1}")
        )
    end

    render(conn, :forgot, sent: true)
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Map.values()
    |> List.flatten()
    |> List.first()
  end
end
