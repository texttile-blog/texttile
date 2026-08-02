defmodule Texttile.Repo do
  use Ecto.Repo,
    otp_app: :texttile,
    adapter: Ecto.Adapters.SQLite3
end
