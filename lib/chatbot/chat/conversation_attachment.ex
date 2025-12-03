defmodule Chatbot.Chat.ConversationAttachment do
  @moduledoc """
  Schema for markdown file attachments to conversations.

  Attachments are stored in the database and automatically deleted
  when the parent conversation is deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @max_file_size 100 * 1024
  @max_attachments_per_conversation 5
  @allowed_extensions ~w(.md .markdown .txt)

  @type t :: %__MODULE__{
          id: binary() | nil,
          conversation_id: binary() | nil,
          filename: String.t() | nil,
          content: String.t() | nil,
          content_type: String.t() | nil,
          size_bytes: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "conversation_attachments" do
    field :filename, :string
    field :content, :string
    field :content_type, :string, default: "text/markdown"
    field :size_bytes, :integer

    belongs_to :conversation, Chatbot.Chat.Conversation

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :content, :content_type, :size_bytes, :conversation_id])
    |> validate_required([:filename, :content, :size_bytes, :conversation_id])
    |> validate_length(:filename, max: 255)
    |> validate_number(:size_bytes, less_than_or_equal_to: @max_file_size)
    |> validate_content_length()
    |> validate_file_extension()
    |> foreign_key_constraint(:conversation_id)
    |> maybe_put_uuid()
  end

  defp validate_content_length(changeset) do
    case get_field(changeset, :content) do
      nil ->
        changeset

      content when is_binary(content) ->
        if byte_size(content) <= @max_file_size do
          changeset
        else
          add_error(changeset, :content, "content exceeds maximum file size")
        end
    end
  end

  defp validate_file_extension(changeset) do
    case get_field(changeset, :filename) do
      nil ->
        changeset

      filename ->
        ext = filename |> Path.extname() |> String.downcase()

        if ext in @allowed_extensions do
          changeset
        else
          add_error(changeset, :filename, "must be a markdown file (.md, .markdown, or .txt)")
        end
    end
  end

  defp maybe_put_uuid(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Chatbot.Repo.generate_uuid())
    end
  end

  @doc "Returns the maximum file size in bytes (100KB)."
  @spec max_file_size() :: pos_integer()
  def max_file_size, do: @max_file_size

  @doc "Returns the maximum number of attachments per conversation (5)."
  @spec max_attachments_per_conversation() :: pos_integer()
  def max_attachments_per_conversation, do: @max_attachments_per_conversation

  @doc "Returns the list of allowed file extensions."
  @spec allowed_extensions() :: [String.t()]
  def allowed_extensions, do: @allowed_extensions
end
