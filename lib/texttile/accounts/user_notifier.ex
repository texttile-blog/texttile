defmodule Texttile.Accounts.UserNotifier do
  @moduledoc """
  Account mail: the link that sets a new password, and nothing else.
  Nothing in here ever contains a password.
  """

  import Swoosh.Email

  alias Texttile.Mailer

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
