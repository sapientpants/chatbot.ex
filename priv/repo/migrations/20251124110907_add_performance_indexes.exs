defmodule Chatbot.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite index for messages - supports queries that fetch messages
    # for a specific conversation ordered by inserted_at
    create_if_not_exists index(:messages, [:conversation_id, :inserted_at])

    # Composite index for conversations - supports queries that fetch
    # a user's conversations ordered by updated_at (most recent first)
    create_if_not_exists index(:conversations, [:user_id, :updated_at])

    # Composite index for user_tokens - supports token cleanup queries
    # and user-specific token lookups by context
    create_if_not_exists index(:user_tokens, [:user_id, :context])

    # Additional index for user_tokens to support expired token cleanup
    # The inserted_at field is used to determine token age for cleanup
    create_if_not_exists index(:user_tokens, [:inserted_at])
  end
end
