defmodule TexttileWeb.SessionController do
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias TexttileWeb.UserAuth

  def new(conn, _params) do
    if Accounts.setup_state() == :done do
      render(conn, :new, error: nil, username: "")
    else
      redirect(conn, to: ~p"/setup")
    end
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    if username == "" or password == "" do
      render(conn, :new, error: :missing, username: username)
    else
      case Accounts.authenticate_user(username, password) do
        {:ok, user} -> UserAuth.log_in_user(conn, user)
        :error -> render(conn, :new, error: :bad, username: username)
      end
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
