defmodule Chatbot.Chat.AttachmentChunk do
  @moduledoc """
  Schema for chunked content from conversation attachments.

  Chunks are stored with vector embeddings for semantic search and have
  a generated tsvector column for full-text keyword search. Each chunk
  maintains references to both its parent attachment and conversation
  for efficient filtering and cascade deletion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          conversation_id: binary() | nil,
          attachment_id: binary() | nil,
          content: String.t() | nil,
          chunk_index: integer() | nil,
          embedding: Pgvector.Ecto.Vector.t() | nil,
          metadata: map() | nil,
          content_hash: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "attachment_chunks" do
    field :content, :string
    field :chunk_index, :integer
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}
    field :content_hash, :string

    belongs_to :conversation, Chatbot.Chat.Conversation
    belongs_to :attachment, Chatbot.Chat.ConversationAttachment

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :content,
      :chunk_index,
      :embedding,
      :metadata,
      :content_hash,
      :conversation_id,
      :attachment_id
    ])
    |> validate_required([:content, :chunk_index, :conversation_id, :attachment_id])
    |> validate_number(:chunk_index, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:attachment_id)
    |> maybe_put_uuid()
    |> maybe_compute_hash()
  end

  defp maybe_put_uuid(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Chatbot.Repo.generate_uuid())
    end
  end

  defp maybe_compute_hash(changeset) do
    case get_change(changeset, :content) do
      nil ->
        changeset

      content ->
        hash = Base.encode16(:crypto.hash(:sha256, content), case: :lower)
        put_change(changeset, :content_hash, hash)
    end
  end
end
