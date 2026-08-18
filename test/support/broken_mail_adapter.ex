defmodule Texttile.BrokenMailAdapter do
  @moduledoc """
  A mail adapter that never delivers, for the tests about what happens
  when the mail server is down: an invitation whose mail cannot leave
  leaves the account standing and says so.
  """

  @behaviour Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :no_mail_server}

  @impl true
  def deliver_many(emails, _config), do: {:error, {:no_mail_server, length(emails)}}

  @impl true
  def validate_config(_config), do: :ok
end
