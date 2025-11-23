defmodule Chatbot.Chat.Message do
  @moduledoc """
  Message schema for chat conversations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tokens_used, :integer
    field :conversation_id, :binary_id

    belongs_to :conversation, Chatbot.Chat.Conversation, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tokens_used, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
    |> foreign_key_constraint(:conversation_id)
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
