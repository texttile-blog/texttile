defmodule Texttile.Repo.Migrations.AddCommentAuthorAccount do
  use Ecto.Migration

  @moduledoc """
  A comment that somebody wrote while signed in points at the account
  that wrote it. The account can go without the comment going with it,
  so the reference is emptied and the name and the address the comment
  carries stay as they were written.
  """

  def change do
    alter table(:comments) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:comments, [:user_id])
  end
end
