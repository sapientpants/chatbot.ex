defmodule Chatbot.Chat.Message do
  @moduledoc """
  Message schema for chat conversations.

  Supports regular chat messages and tool-related messages:
  - Assistant messages may include `tool_calls` when requesting tool execution
  - Tool result messages have role "tool" with `tool_call_id`, `tool_name`, and `tool_result`
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @type rag_source :: %{
          index: integer(),
          filename: String.t(),
          section: String.t() | nil,
          content: String.t()
        }

  @type t :: %__MODULE__{
          id: binary() | nil,
          role: String.t() | nil,
          content: String.t() | nil,
          tokens_used: integer() | nil,
          conversation_id: binary() | nil,
          tool_calls: [tool_call()] | nil,
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          tool_result: map() | nil,
          tool_error: String.t() | nil,
          tool_duration_ms: integer() | nil,
          rag_sources: [rag_source()] | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tokens_used, :integer
    field :conversation_id, :binary_id

    # Tool calling fields
    field :tool_calls, {:array, :map}
    field :tool_call_id, :string
    field :tool_name, :string
    field :tool_result, :map
    field :tool_error, :string
    field :tool_duration_ms, :integer

    # RAG citation sources
    field :rag_sources, {:array, :map}, default: []

    belongs_to :conversation, Chatbot.Chat.Conversation, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :role,
      :content,
      :tokens_used,
      :conversation_id,
      :tool_calls,
      :tool_call_id,
      :tool_name,
      :tool_result,
      :tool_error,
      :tool_duration_ms,
      :rag_sources
    ])
    |> validate_required([:role, :conversation_id])
    |> validate_content_or_tool()
    |> validate_inclusion(:role, ["user", "assistant", "system", "tool"])
    |> validate_tool_message()
    |> foreign_key_constraint(:conversation_id)
    |> maybe_put_uuid()
  end

  # Tool messages must have tool_call_id and tool_name
  defp validate_tool_message(changeset) do
    if get_field(changeset, :role) == "tool" do
      validate_required(changeset, [:tool_call_id, :tool_name])
    else
      changeset
    end
  end

  # Regular messages need content, tool messages need result or error
  defp validate_content_or_tool(changeset) do
    role = get_field(changeset, :role)
    content = get_field(changeset, :content)
    tool_result = get_field(changeset, :tool_result)
    tool_error = get_field(changeset, :tool_error)
    tool_calls = get_field(changeset, :tool_calls)

    cond do
      role == "tool" and (tool_result || tool_error) ->
        changeset

      role == "assistant" and (content || tool_calls) ->
        changeset

      role in ["user", "system"] and content ->
        validate_length(changeset, :content, min: 1, max: 10_000)

      role == "tool" ->
        add_error(changeset, :tool_result, "or tool_error is required for tool messages")

      true ->
        add_error(changeset, :content, "is required")
    end
  end

  defp maybe_put_uuid(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Chatbot.Repo.generate_uuid())
    end
  end

  @doc """
  Checks if this message contains tool calls.
  """
  @spec has_tool_calls?(t()) :: boolean()
  def has_tool_calls?(%__MODULE__{tool_calls: nil}), do: false
  def has_tool_calls?(%__MODULE__{tool_calls: []}), do: false
  def has_tool_calls?(%__MODULE__{tool_calls: _tool_calls}), do: true

  @doc """
  Checks if this is a tool result message.
  """
  @spec tool_result?(t()) :: boolean()
  def tool_result?(%__MODULE__{role: "tool"}), do: true
  def tool_result?(_message), do: false
end
