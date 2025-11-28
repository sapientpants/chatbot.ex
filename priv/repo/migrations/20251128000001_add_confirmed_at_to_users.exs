defmodule Chatbot.Repo.Migrations.AddConfirmedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :confirmed_at, :utc_datetime
    end
  end
end
