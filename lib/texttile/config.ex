defmodule Texttile.Config do
  @moduledoc """
  Reads the host-specific configuration from environment variables.

  Texttile runs anywhere a container runs. The two paths below are the
  full contract between the app and its host: where the SQLite database
  lives and where uploaded files live.
  """

  def database_path(env \\ System.get_env()), do: fetch!(env, "DATABASE_PATH")

  def uploads_path(env \\ System.get_env()), do: fetch!(env, "UPLOADS_PATH")

  @doc """
  Swoosh mailer configuration, chosen by MAIL_ADAPTER.

  Each adapter loads exactly the credential variables it needs. Without
  MAIL_ADAPTER, mails go to the local preview mailbox instead of the network.
  """
  def mailer_config(env \\ System.get_env()) do
    case env["MAIL_ADAPTER"] do
      nil ->
        [adapter: Swoosh.Adapters.Local]

      "resend" ->
        [adapter: Swoosh.Adapters.Resend, api_key: fetch!(env, "RESEND_API_KEY")]

      "postmark" ->
        [adapter: Swoosh.Adapters.Postmark, api_key: fetch!(env, "POSTMARK_API_KEY")]

      "brevo" ->
        [adapter: Swoosh.Adapters.Brevo, api_key: fetch!(env, "BREVO_API_KEY")]

      "ses" ->
        [
          adapter: Swoosh.Adapters.AmazonSES,
          region: fetch!(env, "AWS_REGION"),
          access_key: fetch!(env, "AWS_ACCESS_KEY_ID"),
          secret: fetch!(env, "AWS_SECRET_ACCESS_KEY")
        ]

      "smtp" ->
        [
          adapter: Swoosh.Adapters.SMTP,
          relay: fetch!(env, "SMTP_HOST"),
          port: String.to_integer(env["SMTP_PORT"] || "587"),
          username: fetch!(env, "SMTP_USERNAME"),
          password: fetch!(env, "SMTP_PASSWORD"),
          auth: :always,
          tls: :always
        ]

      other ->
        raise "unknown MAIL_ADAPTER #{inspect(other)}. " <>
                "Valid values: resend, postmark, brevo, smtp, ses. " <>
                "Unset the variable to use the local preview mailbox."
    end
  end

  @doc """
  Sender address for outgoing mail. MAIL_FROM wins; the fallback derives
  from the public hostname.
  """
  def mail_from(env \\ System.get_env()) do
    env["MAIL_FROM"] || "texttile@#{env["PHX_HOST"] || "localhost"}"
  end

  defp fetch!(env, name) do
    env[name] ||
      raise "environment variable #{name} is not set."
  end
end
