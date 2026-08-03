defmodule Texttile.Accounts.UserNotifier do
  @moduledoc """
  Account mail. Nothing in here ever contains a password.
  """

  import Swoosh.Email

  alias Texttile.Mailer

  @doc """
  Confirms a fresh registration: which site, which username. The
  password stays out on purpose.
  """
  def deliver_registration_confirmation(user, site) do
    deliver(user, "Your admin account on #{site}", """
    Hello #{user.username},

    You have an admin account on #{site} now.

    Your username is: #{user.username}

    Sign in with this username and the password you chose. This mail
    does not contain the password, and no mail ever will.
    """)
  end

  defp deliver(user, subject, body) do
    email =
      new()
      |> to({user.username, user.email})
      |> from({"Texttile", Application.fetch_env!(:texttile, :mail_from)})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
