defmodule Texttile.Articles.LogEntry do
  @moduledoc """
  One line of a text's Log: who did what, newest first. A line keeps
  the user id and nothing else about the person; the displayed name is
  looked up at paint time, so a rename never leaves a stale name here.
  """

  use Ecto.Schema

  schema "article_log" do
    field :text, :string

    belongs_to :article, Texttile.Articles.Article
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
