defmodule Texttile.Repo.Migrations.AddDeskMarksToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      # The trash: the moment the row goes for good. Set means deleted,
      # and no list on the desk and no reader page shows it any more.
      add :delete_after, :utc_datetime

      # The desk let this one comment through while its address is still
      # unconfirmed. It marks the comment, never the address: the next
      # comment from the same address waits again.
      add :released_at, :utc_datetime

      # The desk changed the words. `updated_at` cannot say it: every
      # trash, restore and release moves that one too.
      add :edited_at, :utc_datetime
    end

    # What the sweeper asks for, over and over: what is due now.
    create index(:comments, [:delete_after])
  end
end
