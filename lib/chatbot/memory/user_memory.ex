defmodule Chatbot.Memory.UserMemory do
  @moduledoc """
  Schema for user memories - facts and preferences extracted from conversations.

  Memories are stored with vector embeddings for semantic search and have
  a generated tsvector column for full-text keyword search.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          user_id: binary() | nil,
          content: String.t() | nil,
          category: String.t() | nil,
          source_message_id: binary() | nil,
          embedding: Pgvector.Ecto.Vector.t() | nil,
          confidence: float() | nil,
          last_accessed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @categories ~w(preference personal_info skill project context)

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "user_memories" do
    field :content, :string
    field :category, :string
    field :embedding, Pgvector.Ecto.Vector
    field :confidence, :float, default: 1.0
    field :last_accessed_at, :utc_datetime
    field :user_id, :binary_id
    field :source_message_id, :binary_id

    belongs_to :user, Chatbot.Accounts.User, define_field: false
    belongs_to :source_message, Chatbot.Chat.Message, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid memory categories.
  """
  @spec categories() :: [String.t()]
  def categories, do: @categories

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :content,
      :category,
      :embedding,
      :confidence,
      :last_accessed_at,
      :user_id,
      :source_message_id
    ])
    |> validate_required([:content, :user_id])
    |> validate_length(:content, min: 1, max: 5_000)
    |> validate_inclusion(:category, @categories)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:source_message_id)
    |> maybe_put_uuid()
  end

  defp maybe_put_uuid(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Chatbot.Repo.generate_uuid())
    end
  end
end
