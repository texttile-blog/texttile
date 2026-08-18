defmodule TexttileWeb.SessionController do
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias Texttile.RateLimiter
  alias TexttileWeb.ClientIP
  alias TexttileWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new,
      error: nil,
      email: "",
      remember: false,
      nobody_can_sign_in: Accounts.nobody_can_sign_in?()
    )
  end

  @doc """
  The sign-in form. It takes the address of an account and its
  password, and it answers a wrong password and an address without an
  account the same way: this screen never says who has an account here.

  Nobody chooses a password on this screen. An account gets its first
  one through the mailed link, so there is no door here that a stranger
  could walk through by being early.
  """
  def create(conn, %{"user" => %{"email" => email, "password" => password} = params}) do
    cond do
      String.trim(email) == "" or password == "" ->
        again(conn, :missing, email, params)

      not knock(conn) ->
        again(conn, :too_many, email, params)

      true ->
        case Accounts.authenticate_user(email, password) do
          {:ok, user} -> UserAuth.log_in_user(conn, user, remember?(params))
          :error -> again(conn, :bad, email, params)
        end
    end
  end

  defp again(conn, error, email, params) do
    render(conn, :new,
      error: error,
      email: email,
      remember: remember?(params),
      nobody_can_sign_in: Accounts.nobody_can_sign_in?()
    )
  end

  # The box on the form. A browser that does not send it means no.
  defp remember?(%{"remember" => value}), do: value == "true"
  defp remember?(_params), do: false

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  def delete_all(conn, _params) do
    UserAuth.log_out_everywhere(conn)
  end

  # One try at a password door, out of the caller's few per minute.
  defp knock(conn), do: RateLimiter.allow?(ClientIP.of(conn), Accounts.door_limiter())
end
