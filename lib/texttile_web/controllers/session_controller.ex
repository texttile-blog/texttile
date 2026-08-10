defmodule TexttileWeb.SessionController do
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias TexttileWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error: nil, username: "", remember: false)
  end

  @doc """
  The sign-in form. A configured name that has no account yet goes to
  the password screen instead of the password check: nobody has a
  password for it yet, and that screen is where its owner chooses one.
  """
  def create(conn, %{"user" => %{"username" => username, "password" => password} = params}) do
    cond do
      String.trim(username) == "" ->
        render(conn, :new, error: :missing, username: username, remember: remember?(params))

      Accounts.sign_in_state(username) == :claimable ->
        render(conn, :claim, username: String.trim(username), changeset: nil)

      password == "" ->
        render(conn, :new, error: :missing, username: username, remember: remember?(params))

      true ->
        case Accounts.authenticate_user(username, password) do
          {:ok, user} ->
            UserAuth.log_in_user(conn, user, remember?(params))

          :error ->
            render(conn, :new, error: :bad, username: username, remember: remember?(params))
        end
    end
  end

  # The box on the form. A browser that does not send it means no.
  defp remember?(%{"remember" => value}), do: value == "true"
  defp remember?(_params), do: false

  @doc """
  The password screen creates the account and signs it in. A name that
  nobody configured gets the answer of a wrong password, and a name that
  somebody claimed in the meantime goes back to the form.
  """
  def claim(conn, %{"user" => %{"username" => username} = params}) do
    case Accounts.claim_account(username, params, site: TexttileWeb.Endpoint.host()) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, :not_allowed} ->
        render(conn, :new, error: :bad, username: username, remember: false)

      {:error, :taken} ->
        render(conn, :new, error: :claimed, username: username, remember: false)

      {:error, changeset} ->
        render(conn, :claim, username: String.trim(username), changeset: changeset)
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  def delete_all(conn, _params) do
    UserAuth.log_out_everywhere(conn)
  end
end
