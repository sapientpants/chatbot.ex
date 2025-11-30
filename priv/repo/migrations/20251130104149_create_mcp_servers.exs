defmodule Chatbot.Repo.Migrations.CreateMcpServers do
  use Ecto.Migration

  def change do
    create table(:mcp_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text

      # "stdio" | "http"
      add :transport_type, :string, null: false

      # STDIO transport config
      add :command, :string
      add :args, {:array, :string}, default: []
      add :env, :map, default: %{}

      # HTTP transport config
      add :base_url, :string
      add :headers, :map, default: %{}

      add :enabled, :boolean, default: true
      add :global, :boolean, default: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:mcp_servers, [:user_id])
    create index(:mcp_servers, [:global])
    create unique_index(:mcp_servers, [:name, :user_id], name: :mcp_servers_name_user_unique)
  end
end
