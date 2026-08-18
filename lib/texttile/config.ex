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
  The email addresses that get an account, from ADMIN_USERS.

  This is not the guest list of the installation any more: the accounts
  are. The variable is one of the two ways an account comes into being.
  At every start the server takes an address in here that has no account
  yet, makes the account and mails it a link that sets its password. The
  other way is the Users block of Settings, and it needs no deploy.

      ADMIN_USERS="kb@example.org,julia@example.org"

  Addresses arrive as people write them, so spaces and capitals are
  taken out. Anything that is not an address is dropped, because it
  could only ever be a typo. Without the variable the list is empty,
  which is what an installation whose accounts exist already wants.
  """
  def admin_emails(env \\ System.get_env()) do
    (env["ADMIN_USERS"] || "")
    |> String.split(",")
    |> Enum.map(&Texttile.Accounts.User.normalize_email/1)
    |> Enum.filter(&Texttile.Accounts.User.valid_email?/1)
    |> Enum.uniq()
  end

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
        relay = fetch!(env, "SMTP_HOST")

        [
          adapter: Swoosh.Adapters.SMTP,
          relay: relay,
          port: String.to_integer(env["SMTP_PORT"] || "587"),
          username: fetch!(env, "SMTP_USERNAME"),
          password: fetch!(env, "SMTP_PASSWORD"),
          auth: :always,
          tls: :always,
          tls_options: tls_options(relay)
        ]

      other ->
        raise "unknown MAIL_ADAPTER #{inspect(other)}. " <>
                "Valid values: resend, postmark, brevo, smtp, ses. " <>
                "Unset the variable to use the local preview mailbox."
    end
  end

  # Who the SMTP relay has to prove it is. Without this, gen_smtp takes
  # any certificate that is offered, and a machine in the middle reads
  # SMTP_USERNAME, SMTP_PASSWORD and every mail. The certificate is
  # checked against the system's CA store and against the relay's name,
  # which also goes out as the SNI of the handshake.
  defp tls_options(relay) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(relay),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  @doc """
  Sender address for outgoing mail. MAIL_FROM wins; the fallback derives
  from the public hostname.
  """
  def mail_from(env \\ System.get_env()) do
    env["MAIL_FROM"] || "texttile@#{env["PHX_HOST"] || "localhost"}"
  end

  @doc """
  The header that carries the reader's address, from CLIENT_IP_HEADER,
  lowercased. `nil` means: read the address off the socket. Set it only
  where a proxy stands in front and writes the header itself, for
  example `fly-client-ip` on Fly.io. A header the caller may write is a
  header the caller may change, and the comment rate limit counts by it.
  """
  def client_ip_header(env \\ System.get_env()) do
    case env["CLIENT_IP_HEADER"] do
      nil -> nil
      value -> value |> String.trim() |> String.downcase() |> presence()
    end
  end

  defp presence(""), do: nil
  defp presence(value), do: value

  @doc """
  The main checkout of the repository: every linked worktree answers
  with the same directory, so the state that all worktrees share in dev
  lives there (the database, the uploads, the `.env`). Outside a git
  checkout, the directory is its own root.
  """
  def shared_root(cd \\ File.cwd!()) do
    case System.cmd("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"],
           cd: cd,
           stderr_to_stdout: true
         ) do
      {out, 0} -> out |> String.trim() |> Path.dirname()
      _ -> cd
    end
  rescue
    _ -> cd
  end

  @doc """
  Reads a dotenv file. Returns an empty map when the file does not exist.

  In dev, runtime.exs feeds these values into the environment so the
  shared `.env` always applies, no matter how the app is started.
  """
  def dotenv(path \\ ".env") do
    case File.read(path) do
      {:ok, content} -> parse_dotenv(content)
      {:error, _} -> %{}
    end
  end

  @doc false
  def parse_dotenv(content) do
    for line <- String.split(content, "\n"),
        line = String.trim(line),
        line != "" and not String.starts_with?(line, "#"),
        parts = String.split(String.replace_prefix(line, "export ", ""), "=", parts: 2),
        match?([_, _], parts),
        into: %{} do
      [key, value] = parts
      {String.trim(key), value |> String.trim() |> unquote_value()}
    end
  end

  defp unquote_value(<<q, rest::binary>> = value) when q in [?", ?'] do
    size = byte_size(rest) - 1

    case rest do
      <<inner::binary-size(size), ^q>> -> inner
      _ -> value
    end
  end

  defp unquote_value(value), do: value

  defp fetch!(env, name) do
    env[name] ||
      raise "environment variable #{name} is not set."
  end
end
