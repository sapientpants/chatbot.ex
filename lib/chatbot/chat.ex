defmodule Chatbot.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias Chatbot.Repo

  alias Chatbot.Chat.Conversation
  alias Chatbot.Chat.ConversationAttachment
  alias Chatbot.Chat.Message
  alias Chatbot.RAG.ChunkProcessor

  require Logger

  @doc """
  Returns the list of conversations for a user.

  ## Examples

      iex> list_conversations(user_id)
      [%Conversation{}, ...]

  """
  @spec list_conversations(binary()) :: [Conversation.t()]
  def list_conversations(user_id) do
    Conversation
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation for a specific user.

  Raises `Ecto.NoResultsError` if the Conversation does not exist or doesn't belong to the user.

  ## Examples

      iex> get_conversation!(123, user_id)
      %Conversation{}

      iex> get_conversation!(456, user_id)
      ** (Ecto.NoResultsError)

  """
  @spec get_conversation!(binary(), binary()) :: Conversation.t()
  def get_conversation!(id, user_id) do
    Conversation
    |> where([c], c.id == ^id and c.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc """
  Gets a conversation with messages preloaded for a specific user.

  Raises `Ecto.NoResultsError` if the Conversation does not exist or doesn't belong to the user.

  ## Options

    * `:limit` - Maximum number of messages to load (default: 100)
    * `:offset` - Number of messages to skip (default: 0)

  ## Examples

      iex> get_conversation_with_messages!(123, user_id)
      %Conversation{messages: [%Message{}, ...]}

      iex> get_conversation_with_messages!(123, user_id, limit: 50)
      %Conversation{messages: [%Message{}, ...]}

  """
  @spec get_conversation_with_messages!(binary(), binary(), keyword()) :: Conversation.t()
  def get_conversation_with_messages!(id, user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    message_query =
      from(m in Message,
        order_by: m.inserted_at,
        limit: ^limit,
        offset: ^offset
      )

    Conversation
    |> where([c], c.id == ^id and c.user_id == ^user_id)
    |> preload([c], messages: ^message_query)
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
  @spec create_conversation(map()) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
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
  @spec update_conversation(Conversation.t(), map()) ::
          {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation if it belongs to the specified user.

  ## Examples

      iex> delete_conversation(conversation, user_id)
      {:ok, %Conversation{}}

      iex> delete_conversation(conversation, different_user_id)
      {:error, :unauthorized}

  """
  @spec delete_conversation(Conversation.t(), binary()) ::
          {:ok, Conversation.t()} | {:error, :unauthorized | Ecto.Changeset.t()}
  def delete_conversation(%Conversation{} = conversation, user_id) do
    if conversation.user_id == user_id do
      Repo.delete(conversation)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking conversation changes.

  ## Examples

      iex> change_conversation(conversation)
      %Ecto.Changeset{data: %Conversation{}}

  """
  @spec change_conversation(Conversation.t(), map()) :: Ecto.Changeset.t()
  def change_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    Conversation.changeset(conversation, attrs)
  end

  @doc """
  Verifies that a conversation belongs to a specific user.

  Returns `{:ok, conversation}` if authorized, `{:error, :unauthorized}` otherwise.

  ## Examples

      iex> verify_conversation_access(conversation_id, user_id)
      {:ok, %Conversation{}}

      iex> verify_conversation_access(conversation_id, wrong_user_id)
      {:error, :unauthorized}

  """
  @spec verify_conversation_access(binary(), binary()) ::
          {:ok, Conversation.t()} | {:error, :unauthorized}
  def verify_conversation_access(conversation_id, user_id) do
    case Repo.get_by(Conversation, id: conversation_id, user_id: user_id) do
      nil -> {:error, :unauthorized}
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Returns the list of messages for a conversation.

  ## Options

    * `:limit` - Maximum number of messages to return (default: all)
    * `:offset` - Number of messages to skip (default: 0)

  ## Examples

      iex> list_messages(conversation_id)
      [%Message{}, ...]

      iex> list_messages(conversation_id, limit: 50, offset: 0)
      [%Message{}, ...]

  """
  @spec list_messages(binary(), keyword()) :: [Message.t()]
  def list_messages(conversation_id, opts \\ []) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> maybe_offset(Keyword.get(opts, :offset))
    |> Repo.all()
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, 0), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  @doc """
  Creates a message.

  ## Examples

      iex> create_message(%{field: value})
      {:ok, %Message{}}

      iex> create_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
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
  @spec generate_conversation_title(String.t() | any()) :: String.t()
  def generate_conversation_title(first_message) when is_binary(first_message) do
    case String.trim(first_message) do
      "" ->
        "New Conversation"

      message ->
        String.slice(message, 0, 50) <> if String.length(message) > 50, do: "...", else: ""
    end
  end

  @spec generate_conversation_title(any()) :: String.t()
  def generate_conversation_title(_message), do: "New Conversation"

  @doc """
  Builds messages in OpenAI format for API calls.

  ## Examples

      iex> build_openai_messages([%Message{role: "user", content: "Hello"}])
      [%{role: "user", content: "Hello"}]

  """
  @spec build_openai_messages([Message.t()]) :: [%{role: String.t(), content: String.t()}]
  def build_openai_messages(messages) do
    Enum.map(messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
  end

  # ============================================
  # Attachment Functions
  # ============================================

  @doc """
  Lists all attachments for a conversation.

  ## Examples

      iex> list_attachments(conversation_id)
      [%ConversationAttachment{}, ...]

  """
  @spec list_attachments(binary()) :: [ConversationAttachment.t()]
  def list_attachments(conversation_id) do
    ConversationAttachment
    |> where([a], a.conversation_id == ^conversation_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single attachment.

  Returns nil if not found.
  """
  @spec get_attachment(binary()) :: ConversationAttachment.t() | nil
  def get_attachment(id) do
    Repo.get(ConversationAttachment, id)
  end

  @doc """
  Gets an attachment with authorization check.

  Returns `{:ok, attachment}` if found and belongs to user's conversation,
  `{:error, :not_found}` otherwise.
  """
  @spec get_attachment_for_user(binary(), binary()) ::
          {:ok, ConversationAttachment.t()} | {:error, :not_found}
  def get_attachment_for_user(attachment_id, user_id) do
    query =
      from a in ConversationAttachment,
        join: c in Conversation,
        on: a.conversation_id == c.id,
        where: a.id == ^attachment_id and c.user_id == ^user_id,
        select: a

    case Repo.one(query) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  @doc """
  Creates an attachment for a conversation.

  Validates that the conversation hasn't exceeded the maximum attachment limit.

  ## Examples

      iex> create_attachment(%{conversation_id: id, filename: "notes.md", content: "...", size_bytes: 1024})
      {:ok, %ConversationAttachment{}}

      iex> create_attachment(%{conversation_id: id, ...}) # when at limit
      {:error, :attachment_limit_exceeded}

  """
  @spec create_attachment(map()) ::
          {:ok, ConversationAttachment.t()}
          | {:error, Ecto.Changeset.t() | :attachment_limit_exceeded}
  def create_attachment(attrs) do
    conversation_id = attrs[:conversation_id] || attrs["conversation_id"]

    # If no conversation_id provided, let changeset validation handle it
    if conversation_id do
      current_count = attachment_count(conversation_id)
      max_count = ConversationAttachment.max_attachments_per_conversation()

      if current_count >= max_count do
        {:error, :attachment_limit_exceeded}
      else
        do_create_attachment_with_chunks(attrs)
      end
    else
      do_create_attachment_with_chunks(attrs)
    end
  end

  defp do_create_attachment_with_chunks(attrs) do
    # Skip transaction overhead when RAG is disabled
    if rag_enabled?() do
      Repo.transaction(fn ->
        with {:ok, attachment} <- do_create_attachment(attrs),
             {:ok, _chunks} <- process_attachment_chunks(attachment) do
          attachment
        else
          {:error, reason} ->
            Logger.error("Failed to create attachment with chunks: #{inspect(reason)}")
            Repo.rollback(reason)
        end
      end)
    else
      do_create_attachment(attrs)
    end
  end

  defp do_create_attachment(attrs) do
    %ConversationAttachment{}
    |> ConversationAttachment.changeset(attrs)
    |> Repo.insert()
  end

  defp process_attachment_chunks(attachment) do
    if rag_enabled?() do
      ChunkProcessor.process_attachment(attachment)
    else
      {:ok, []}
    end
  end

  defp rag_enabled? do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, :enabled, true)
  end

  @doc """
  Deletes an attachment.

  ## Examples

      iex> delete_attachment(attachment)
      {:ok, %ConversationAttachment{}}

  """
  @spec delete_attachment(ConversationAttachment.t()) ::
          {:ok, ConversationAttachment.t()} | {:error, Ecto.Changeset.t()}
  def delete_attachment(%ConversationAttachment{} = attachment) do
    Repo.delete(attachment)
  end

  @doc """
  Deletes an attachment with authorization check.

  Returns `{:ok, attachment}` if deleted, `{:error, :not_found}` if not found
  or unauthorized, `{:error, changeset}` on delete failure.
  """
  @spec delete_attachment_for_user(binary(), binary()) ::
          {:ok, ConversationAttachment.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_attachment_for_user(attachment_id, user_id) do
    case get_attachment_for_user(attachment_id, user_id) do
      {:ok, attachment} -> delete_attachment(attachment)
      error -> error
    end
  end

  @doc """
  Returns the count of attachments for a conversation.
  """
  @spec attachment_count(binary()) :: non_neg_integer()
  def attachment_count(conversation_id) do
    ConversationAttachment
    |> where([a], a.conversation_id == ^conversation_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns the total size of all attachments for a conversation in bytes.
  """
  @spec total_attachment_size(binary()) :: non_neg_integer()
  def total_attachment_size(conversation_id) do
    ConversationAttachment
    |> where([a], a.conversation_id == ^conversation_id)
    |> Repo.aggregate(:sum, :size_bytes) || 0
  end

  @doc """
  Checks if a conversation can accept more attachments.
  """
  @spec can_add_attachment?(binary()) :: boolean()
  def can_add_attachment?(conversation_id) do
    attachment_count(conversation_id) < ConversationAttachment.max_attachments_per_conversation()
  end
end
