defmodule Texttile.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Texttile.Accounts` context.
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

  def user_fixture(attrs \\ %{}) do
    {:ok, user} = Accounts.insert_user(valid_user_attributes(attrs))
    user
  end
end
