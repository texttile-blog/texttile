defmodule TexttileWeb.SessionController do
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias Texttile.RateLimiter
  alias TexttileWeb.ClaimInvite
  alias TexttileWeb.ClientIP
  alias TexttileWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error: nil, username: "", remember: false)
  end

  @doc """
  The sign-in form. The first name of an empty installation goes to the
  password screen instead of the password check: nobody has a password
  for it yet, and that screen is where its owner chooses one. Every name
  after that one needs an invitation and gets the answer of a wrong
  password here, so the form never says which names are still free.
  """
  def create(conn, %{"user" => %{"username" => username, "password" => password} = params}) do
    cond do
      String.trim(username) == "" ->
        render(conn, :new, error: :missing, username: username, remember: remember?(params))

      not knock(conn) ->
        render(conn, :new, error: :too_many, username: username, remember: remember?(params))

      Accounts.open_claim?(username) ->
        render(conn, :claim, username: String.trim(username), invite: nil, changeset: nil)

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

  @doc """
  The invitation link an admin handed out. It names the one name it
  opens, and it opens nothing once that name has an account.
  """
  def invited(conn, params) do
    token = to_string(params["invite"])

    case ClaimInvite.verify(token) do
      {:ok, username} ->
        render(conn, :claim, username: username, invite: token, changeset: nil)

      :error ->
        render(conn, :new, error: :invite, username: "", remember: false)
    end
  end

  # The box on the form. A browser that does not send it means no.
  defp remember?(%{"remember" => value}), do: value == "true"
  defp remember?(_params), do: false

  @doc """
  The password screen creates the account and signs it in. A name that
  nobody configured, and a name that carries no invitation, get the
  answer of a wrong password; a name that somebody claimed in the
  meantime goes back to the form.
  """
  def claim(conn, %{"user" => %{"username" => username} = params}) do
    invite = to_string(params["invite"])

    if knock(conn) do
      opts = [site: TexttileWeb.Endpoint.host(), invited: ClaimInvite.opens?(invite, username)]

      case Accounts.claim_account(username, params, opts) do
        {:ok, user} ->
          UserAuth.log_in_user(conn, user)

        {:error, :not_allowed} ->
          render(conn, :new, error: :bad, username: username, remember: false)

        {:error, :taken} ->
          render(conn, :new, error: :claimed, username: username, remember: false)

        {:error, changeset} ->
          render(conn, :claim,
            username: String.trim(username),
            invite: invite,
            changeset: changeset
          )
      end
    else
      render(conn, :new, error: :too_many, username: username, remember: false)
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  def delete_all(conn, _params) do
    UserAuth.log_out_everywhere(conn)
  end

  # One try at a password door, out of the caller's few per minute.
  defp knock(conn), do: RateLimiter.allow?(ClientIP.of(conn), Accounts.door_limiter())
end
