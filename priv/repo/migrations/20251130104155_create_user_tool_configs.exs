defmodule Chatbot.Repo.Migrations.CreateUserToolConfigs do
  use Ecto.Migration

  def change do
    create table(:user_tool_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :mcp_server_id, references(:mcp_servers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tool_name, :string, null: false
      add :enabled, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:user_tool_configs, [:user_id])

    create unique_index(:user_tool_configs, [:user_id, :mcp_server_id, :tool_name],
             name: :user_tool_configs_unique
           )
  end
end
