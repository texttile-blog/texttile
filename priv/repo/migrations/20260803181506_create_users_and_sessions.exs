defmodule Texttile.Repo.Migrations.CreateUsersAndSessions do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false
      add :display_name, :string
      add :email, :string, null: false
      add :password_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:email])

    create table(:sessions) do
      add :token, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:sessions, [:token])
    create index(:sessions, [:user_id])
  end
end
