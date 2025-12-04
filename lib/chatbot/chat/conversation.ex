defmodule Chatbot.Chat.Conversation do
  @moduledoc """
  Conversation schema for chat threads.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          title: String.t() | nil,
          model_name: String.t() | nil,
          user_id: binary() | nil,
          messages: [Chatbot.Chat.Message.t()] | Ecto.Association.NotLoaded.t(),
          attachments: [Chatbot.Chat.ConversationAttachment.t()] | Ecto.Association.NotLoaded.t(),
          chunks: [Chatbot.Chat.AttachmentChunk.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :title, :string
    field :model_name, :string
    field :user_id, :binary_id

    belongs_to :user, Chatbot.Accounts.User, define_field: false
    has_many :messages, Chatbot.Chat.Message
    has_many :attachments, Chatbot.Chat.ConversationAttachment
    has_many :chunks, Chatbot.Chat.AttachmentChunk

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :model_name, :user_id])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
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
