defmodule Chatbot.Repo.Migrations.CreateSystemSettings do
  use Ecto.Migration

  def change do
    create table(:system_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text

      timestamps(type: :utc_datetime)
    end
  end
end
