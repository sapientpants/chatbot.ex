defmodule Chatbot.Repo.Migrations.CreateUserMemories do
  use Ecto.Migration

  def up do
    create table(:user_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :content, :text, null: false
      add :category, :string
      add :source_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :embedding, :vector, size: 1024
      add :confidence, :float, default: 1.0
      add :last_accessed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Full-text search column using GIN index
    execute """
    ALTER TABLE user_memories ADD COLUMN searchable tsvector
    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
    """

    create index(:user_memories, [:user_id])
    create index(:user_memories, [:user_id, :category])
    create index(:user_memories, [:searchable], using: :gin)

    # HNSW index for vector similarity search
    execute """
    CREATE INDEX user_memories_embedding_idx ON user_memories
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
    """
  end

  def down do
    drop table(:user_memories)
  end
end
