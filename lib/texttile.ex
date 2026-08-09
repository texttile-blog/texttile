defmodule Texttile do
  @moduledoc """
  Texttile keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  The version of this installation, the number `mix.exs` carries.

  Every pull request raises it, so the number alone says which build
  runs: the image on the registry has no git in it, and nothing else
  in a running container tells you what it was made from. Settings
  shows it, behind the sign-in, because a version number in the open
  tells an attacker which holes to try.
  """
  @spec version() :: String.t()
  def version do
    :texttile |> Application.spec(:vsn) |> to_string()
  end
end
