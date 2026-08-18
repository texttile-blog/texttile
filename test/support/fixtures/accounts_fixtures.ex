defmodule Texttile.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Texttile.Accounts` context.

  `user_fixture/1` makes what an invitation plus a followed link makes:
  an account with an address and a password. `invited_user_fixture/1`
  stops halfway, at the account that is still waiting for its first
  password. `configure_admin_emails/1` sets ADMIN_USERS for the tests
  that are about the variable itself; `Texttile.DataCase` puts it back
  after every test.
  """

  alias Texttile.Accounts
  alias Texttile.Accounts.User
  alias Texttile.Repo

  def valid_password, do: "correct horse battery"

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.org"

  @doc "An account that can sign in: an address, a password, maybe a name."
  def user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{email: unique_email(), password: valid_password()})

    {:ok, user} =
      attrs.email
      |> invited_user_fixture()
      |> User.password_changeset(%{password: attrs.password})
      |> Repo.update()

    case attrs[:display_name] do
      nil ->
        user

      name ->
        {:ok, user} = Accounts.update_display_name(user, name)
        user
    end
  end

  @doc "An invited account, the way Settings and ADMIN_USERS make one: no password yet."
  def invited_user_fixture(email \\ nil) do
    {:ok, user} =
      %User{}
      |> User.invite_changeset(%{email: email || unique_email()})
      |> Repo.insert()

    user
  end

  @doc "Sets the addresses ADMIN_USERS holds, exactly as given."
  def configure_admin_emails(emails) do
    Application.put_env(:texttile, :admin_emails, Enum.uniq(emails))
    :ok
  end

  @doc """
  Takes the mail server away for this test: every mail answers an error
  from here on, and the test that follows gets its mailbox back.
  """
  def break_mail do
    previous = Application.get_env(:texttile, Texttile.Mailer)
    Application.put_env(:texttile, Texttile.Mailer, adapter: Texttile.BrokenMailAdapter)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:texttile, Texttile.Mailer, previous) end)
    :ok
  end
end
