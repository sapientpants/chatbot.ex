defmodule Chatbot.Memory.ConversationSummary do
  @moduledoc """
  Schema for conversation summaries - compressed representations of older messages.

  Summaries are generated when conversations exceed a certain length, allowing
  the context builder to include more historical context within the token budget.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary() | nil,
          conversation_id: binary() | nil,
          content: String.t() | nil,
          message_range_start: integer() | nil,
          message_range_end: integer() | nil,
          token_count: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "conversation_summaries" do
    field :content, :string
    field :message_range_start, :integer
    field :message_range_end, :integer
    field :token_count, :integer
    field :conversation_id, :binary_id

    belongs_to :conversation, Chatbot.Chat.Conversation, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :content,
      :message_range_start,
      :message_range_end,
      :token_count,
      :conversation_id
    ])
    |> validate_required([:content, :message_range_start, :message_range_end, :conversation_id])
    |> validate_length(:content, min: 1)
    |> validate_number(:message_range_start, greater_than_or_equal_to: 0)
    |> validate_number(:message_range_end, greater_than: 0)
    |> validate_range_order()
    |> foreign_key_constraint(:conversation_id)
    |> unique_constraint([:conversation_id, :message_range_start])
    |> maybe_put_uuid()
  end

  defp validate_range_order(changeset) do
    start_idx = get_field(changeset, :message_range_start)
    end_idx = get_field(changeset, :message_range_end)

    if start_idx && end_idx && start_idx >= end_idx do
      add_error(changeset, :message_range_end, "must be greater than message_range_start")
    else
      changeset
    end
  end

  defp maybe_put_uuid(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Chatbot.Repo.generate_uuid())
    end
  end
end
