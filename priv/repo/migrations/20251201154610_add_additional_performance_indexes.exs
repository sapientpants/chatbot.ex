defmodule Chatbot.Repo.Migrations.AddAdditionalPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite index for MCP servers - supports queries filtering by enabled status
    # combined with global/user ownership
    create_if_not_exists index(:mcp_servers, [:enabled, :global])

    # Index for user_memories last_accessed_at - supports memory decay/cleanup queries
    create_if_not_exists index(:user_memories, [:last_accessed_at])

    # Composite index for user_memories - supports confidence filtering per user
    create_if_not_exists index(:user_memories, [:user_id, :confidence])

    # Index for user_tool_configs mcp_server_id - supports lookups by server
    create_if_not_exists index(:user_tool_configs, [:mcp_server_id])
  end
end
