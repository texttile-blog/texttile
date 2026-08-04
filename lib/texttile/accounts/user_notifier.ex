defmodule Texttile.Accounts.UserNotifier do
  @moduledoc """
  Account mail: the confirmation of a fresh account and the link that
  sets a new password. Nothing in here ever contains a password.
  """

  import Swoosh.Email

  alias Texttile.Mailer
  alias Texttile.Settings

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

  # The reader knows the site by its title, not by the product it runs
  # on, so the title is the sender name.
  defp deliver(user, subject, body) do
    email =
      new()
      |> to({user.username, user.email})
      |> from({Settings.site_title(), Application.fetch_env!(:texttile, :mail_from)})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
