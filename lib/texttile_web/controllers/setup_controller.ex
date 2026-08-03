defmodule TexttileWeb.SetupController do
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias TexttileWeb.UserAuth

  def new(conn, _params) do
    case Accounts.setup_state() do
      :open -> render(conn, :new, changeset: nil)
      :closed -> render(conn, :closed)
      :done -> redirect(conn, to: ~p"/login")
    end
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_first_admin(user_params, site: conn.host) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, :done} ->
        redirect(conn, to: ~p"/login")

      {:error, :closed} ->
        render(conn, :closed)

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
