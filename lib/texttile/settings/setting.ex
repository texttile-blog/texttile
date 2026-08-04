defmodule Texttile.Settings.Setting do
  @moduledoc """
  One stored setting: a key and its value as text. Which keys exist,
  their types and their defaults live in `Texttile.Settings`.
  """

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field :value, :string
  end
end
