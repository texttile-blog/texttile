defmodule Texttile.Repo.Migrations.CreateNewsletterSubscribers do
  use Ecto.Migration

  def change do
    # One row per address on the list. The token travels in every mail
    # the address gets: it confirms the address, and it takes it off
    # the list again.
    create table(:newsletter_subscribers) do
      add :email, :string, null: false
      add :token, :string, null: false
      add :confirmed_at, :utc_datetime
      add :confirmation_mailed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:newsletter_subscribers, [:email])
    create unique_index(:newsletter_subscribers, [:token])
  end
end
