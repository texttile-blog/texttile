defmodule TexttileWeb.ClaimInvite do
  @moduledoc """
  The invitation that opens the first sign-in of a name.

  A configured name that has no account yet belongs to nobody, and the
  names are no secret: they stand under the entries their owners wrote.
  So after the first account exists, the password screen opens only for
  a caller who carries an invitation. An admin hands one out in
  Settings > Users and passes the link to their co-author.

  The invitation is a signed sentence, not a row: `SECRET_KEY_BASE`
  carries it, so nothing is stored and nothing has to be swept. It says
  one name, it holds for a week, and it opens nothing once the name has
  an account.
  """

  @salt "claim invite"
  @validity_in_seconds 7 * 24 * 60 * 60

  @doc "How long an invitation holds, in seconds."
  def validity_in_seconds, do: @validity_in_seconds

  @doc "A fresh invitation for the name."
  def sign(username) when is_binary(username) do
    Phoenix.Token.sign(TexttileWeb.Endpoint, @salt, String.downcase(String.trim(username)))
  end

  @doc """
  The name a fresh invitation opens, while that name is still waiting
  for its account. Anything else is `:error`.
  """
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TexttileWeb.Endpoint, @salt, token, max_age: @validity_in_seconds) do
      {:ok, username} ->
        if Texttile.Accounts.sign_in_state(username) == :claimable,
          do: {:ok, username},
          else: :error

      {:error, _reason} ->
        :error
    end
  end

  def verify(_token), do: :error

  @doc "Whether this invitation opens this name."
  def opens?(token, username) when is_binary(token) and is_binary(username) do
    case verify(token) do
      {:ok, name} -> name == String.downcase(String.trim(username))
      :error -> false
    end
  end

  def opens?(_token, _username), do: false
end
