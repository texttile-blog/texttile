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

  @doc """
  Invites the owner of a fresh account: the site, the username, the
  set-a-password link. Nobody chose a password for them; the link is
  where they pick their own.
  """
  def deliver_invitation(user, url, site) do
    deliver(user, "Your admin account on #{site}", """
    Hello #{user.username},

    You have an admin account on #{site} now. An admin there created it
    for you.

    Your username is: #{user.username}

    Open this link and pick your own password:

    #{url}

    The link works once and for 24 hours. If it has run out, ask an
    admin on #{site} to send the invitation again.
    """)
  end

  @doc """
  Mails a password reset: the link where the owner sets a new password
  themselves. Nobody types a password for anybody else.
  """
  def deliver_password_reset(user, url, site) do
    deliver(user, "Set a new password on #{site}", """
    Hello #{user.username},

    Somebody asked for a password reset for your account on #{site}.

    Open this link and set a new password:

    #{url}

    The link works once and for 24 hours. The old password works until
    you set the new one. If you did not ask for this, you can ignore
    this mail.
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
