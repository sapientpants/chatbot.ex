defmodule Chatbot.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string
      add :model_name, :string

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:user_id])
  end
end
