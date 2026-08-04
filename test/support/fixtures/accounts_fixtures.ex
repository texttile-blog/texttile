defmodule Texttile.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Texttile.Accounts` context.

  An account only counts while its username stands in the configuration,
  so `user_fixture/1` puts the name there. `configure_admins/1` sets the
  list on its own, for the tests that are about the list itself.
  `Texttile.DataCase` puts the configured list back after every test.
  """

  alias Texttile.Accounts

  def valid_password, do: "correct horse battery"

  def unique_username, do: "user#{System.unique_integer([:positive])}"

  def valid_user_attributes(attrs \\ %{}) do
    username = unique_username()

    Enum.into(attrs, %{
      username: username,
      email: "#{username}@example.org",
      password: valid_password()
    })
  end

  @doc """
  Creates an account the way the app does: the name is configured, its
  owner claims it with a password, and the address arrives afterwards
  from the profile.
  """
  def user_fixture(attrs \\ %{}) do
    attrs = valid_user_attributes(attrs)
    configure_admins([attrs.username | Accounts.admin_usernames()])
    {:ok, user} = Accounts.claim_account(attrs.username, attrs.password)
    {:ok, user} = Accounts.update_email(user, attrs.email)
    user
  end

  @doc "Sets the configured admin usernames, exactly as given."
  def configure_admins(usernames) do
    Application.put_env(:texttile, :admin_users, Enum.uniq(usernames))
    :ok
  end
end
