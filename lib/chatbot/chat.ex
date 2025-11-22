defmodule Chatbot.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias Chatbot.Repo

  alias Chatbot.Chat.Conversation
  alias Chatbot.Chat.Message

  @doc """
  Returns the list of conversations for a user.

  ## Examples

      iex> list_conversations(user_id)
      [%Conversation{}, ...]

  """
  def list_conversations(user_id) do
    Conversation
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation.

  Raises `Ecto.NoResultsError` if the Conversation does not exist.

  ## Examples

      iex> get_conversation!(123)
      %Conversation{}

      iex> get_conversation!(456)
      ** (Ecto.NoResultsError)

  """
  def get_conversation!(id), do: Repo.get!(Conversation, id)

  @doc """
  Gets a conversation with messages preloaded.

  ## Examples

      iex> get_conversation_with_messages!(123)
      %Conversation{messages: [%Message{}, ...]}

  """
  def get_conversation_with_messages!(id) do
    Conversation
    |> where([c], c.id == ^id)
    |> preload([c], messages: ^from(m in Message, order_by: m.inserted_at))
    |> Repo.one!()
  end

  @doc """
  Creates a conversation.

  ## Examples

      iex> create_conversation(%{field: value})
      {:ok, %Conversation{}}

      iex> create_conversation(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation.

  ## Examples

      iex> update_conversation(conversation, %{field: new_value})
      {:ok, %Conversation{}}

      iex> update_conversation(conversation, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation.

  ## Examples

      iex> delete_conversation(conversation)
      {:ok, %Conversation{}}

      iex> delete_conversation(conversation)
      {:error, %Ecto.Changeset{}}

  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking conversation changes.

  ## Examples

      iex> change_conversation(conversation)
      %Ecto.Changeset{data: %Conversation{}}

  """
  def change_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    Conversation.changeset(conversation, attrs)
  end

  @doc """
  Creates a message.

  ## Examples

      iex> create_message(%{field: value})
      {:ok, %Message{}}

      iex> create_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Generates a title for a conversation based on the first user message.
  Returns first 50 characters of the message or "New Conversation" if empty.

  ## Examples

      iex> generate_conversation_title("Hello, how are you?")
      "Hello, how are you?"

      iex> generate_conversation_title("This is a very long message that should be truncated...")
      "This is a very long message that should be trunca..."

  """
  def generate_conversation_title(first_message) when is_binary(first_message) do
    case String.trim(first_message) do
      "" ->
        "New Conversation"

      message ->
        String.slice(message, 0, 50) <> if String.length(message) > 50, do: "...", else: ""
    end
  end

  def generate_conversation_title(_), do: "New Conversation"

  @doc """
  Builds messages in OpenAI format for API calls.

  ## Examples

      iex> build_openai_messages([%Message{role: "user", content: "Hello"}])
      [%{role: "user", content: "Hello"}]

  """
  def build_openai_messages(messages) do
    Enum.map(messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
  end
end
