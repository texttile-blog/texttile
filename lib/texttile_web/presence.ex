defmodule TexttileWeb.Presence do
  @moduledoc """
  Who is in the admin area right now. One topic for the whole site, one
  key per user, one meta entry per open tab.
  """

  use Phoenix.Presence,
    otp_app: :texttile,
    pubsub_server: Texttile.PubSub
end
