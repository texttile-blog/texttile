defmodule Texttile.Accounts.Scope do
  @moduledoc """
  The identity of the current request: who is signed in, and with which
  session. See https://hexdocs.pm/phoenix/scopes.html.
  """

  alias Texttile.Accounts.User

  defstruct user: nil, session_token: nil

  def for_user(user, session_token \\ nil)

  def for_user(%User{} = user, session_token) do
    %__MODULE__{user: user, session_token: session_token}
  end

  def for_user(nil, _session_token), do: nil
end
