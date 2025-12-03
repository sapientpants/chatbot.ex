defmodule Chatbot.Repo.Migrations.CreateAttachmentChunks do
  use Ecto.Migration

  def up do
    create table(:attachment_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :attachment_id,
          references(:conversation_attachments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :content, :text, null: false
      add :chunk_index, :integer, null: false
      add :embedding, :vector, size: 1024
      add :metadata, :map, default: %{}
      add :content_hash, :string, size: 64

      timestamps(type: :utc_datetime)
    end

    # Full-text search column using GIN index
    execute """
    ALTER TABLE attachment_chunks ADD COLUMN searchable tsvector
    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
    """

    # Indexes for filtering and lookups
    create index(:attachment_chunks, [:conversation_id])
    create index(:attachment_chunks, [:attachment_id])
    create index(:attachment_chunks, [:conversation_id, :attachment_id])
    create index(:attachment_chunks, [:content_hash])

    # GIN index for full-text search
    create index(:attachment_chunks, [:searchable], using: :gin)

    # HNSW index for vector similarity search (cosine distance)
    execute """
    CREATE INDEX attachment_chunks_embedding_idx ON attachment_chunks
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)
    """
  end

  def down do
    drop table(:attachment_chunks)
  end
end
