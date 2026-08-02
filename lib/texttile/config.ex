defmodule Texttile.Config do
  @moduledoc """
  Reads the host-specific configuration from environment variables.

  Texttile runs anywhere a container runs. The two paths below are the
  full contract between the app and its host: where the SQLite database
  lives and where uploaded files live.
  """

  def database_path(env \\ System.get_env()), do: fetch!(env, "DATABASE_PATH")

  def uploads_path(env \\ System.get_env()), do: fetch!(env, "UPLOADS_PATH")

  defp fetch!(env, name) do
    env[name] ||
      raise "environment variable #{name} is not set. " <>
              "Set it to an absolute path on a writable volume."
  end
end
