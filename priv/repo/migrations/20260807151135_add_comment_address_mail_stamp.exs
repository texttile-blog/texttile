defmodule Texttile.Repo.Migrations.AddCommentAddressMailStamp do
  use Ecto.Migration

  def change do
    # When the address last got its confirmation link. One mail per
    # address per hour, so nobody can use the form to mail a stranger.
    alter table(:comment_addresses) do
      add :confirmation_mailed_at, :utc_datetime
    end
  end
end
