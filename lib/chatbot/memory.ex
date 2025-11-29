defmodule Chatbot.Memory do
  @moduledoc """
  The Memory context.

  Provides functions for managing user memories (facts and preferences)
  and conversation summaries. Memories are stored with vector embeddings
  for semantic search.
  """

  import Ecto.Query, warn: false

  alias Chatbot.Memory.ConversationSummary
  alias Chatbot.Memory.UserMemory
  alias Chatbot.Ollama
  alias Chatbot.Repo

  # --- User Memories ---

  @doc """
  Returns the list of memories for a user.

  ## Options

    * `:category` - Filter by category (optional)
    * `:limit` - Maximum number of memories to return (default: 100)

  ## Examples

      iex> list_memories(user_id)
      [%UserMemory{}, ...]

      iex> list_memories(user_id, category: "preference")
      [%UserMemory{}, ...]

  """
  @spec list_memories(binary(), keyword()) :: [UserMemory.t()]
  def list_memories(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    category = Keyword.get(opts, :category)

    UserMemory
    |> where([m], m.user_id == ^user_id)
    |> maybe_filter_category(category)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, category), do: where(query, [m], m.category == ^category)

  @doc """
  Gets a single memory.

  Raises `Ecto.NoResultsError` if the memory does not exist.

  ## Examples

      iex> get_memory!(123)
      %UserMemory{}

      iex> get_memory!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_memory!(binary()) :: UserMemory.t()
  def get_memory!(id), do: Repo.get!(UserMemory, id)

  @doc """
  Gets a single memory for a specific user.

  Returns `nil` if the memory does not exist or doesn't belong to the user.

  ## Examples

      iex> get_user_memory(memory_id, user_id)
      %UserMemory{}

      iex> get_user_memory(memory_id, wrong_user_id)
      nil

  """
  @spec get_user_memory(binary(), binary()) :: UserMemory.t() | nil
  def get_user_memory(id, user_id) do
    UserMemory
    |> where([m], m.id == ^id and m.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Creates a memory with embedding generation.

  Automatically generates an embedding for the content using Ollama.

  ## Examples

      iex> create_memory(%{content: "User prefers dark mode", user_id: user_id})
      {:ok, %UserMemory{}}

      iex> create_memory(%{content: "", user_id: user_id})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_memory(map()) :: {:ok, UserMemory.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def create_memory(attrs) do
    with {:ok, embedding} <- generate_embedding(attrs[:content] || attrs["content"]) do
      attrs_with_embedding = Map.put(attrs, :embedding, embedding)

      %UserMemory{}
      |> UserMemory.changeset(attrs_with_embedding)
      |> Repo.insert()
    end
  end

  @doc """
  Creates a memory without generating an embedding.

  Use this when you already have the embedding or want to add it later.

  ## Examples

      iex> create_memory_without_embedding(%{content: "...", user_id: user_id})
      {:ok, %UserMemory{}}

  """
  @spec create_memory_without_embedding(map()) ::
          {:ok, UserMemory.t()} | {:error, Ecto.Changeset.t()}
  def create_memory_without_embedding(attrs) do
    %UserMemory{}
    |> UserMemory.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a memory.

  If content is changed, regenerates the embedding.

  ## Examples

      iex> update_memory(memory, %{content: "Updated content"})
      {:ok, %UserMemory{}}

  """
  @spec update_memory(UserMemory.t(), map()) ::
          {:ok, UserMemory.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def update_memory(%UserMemory{} = memory, attrs) do
    new_content = attrs[:content] || attrs["content"]

    attrs =
      if new_content && new_content != memory.content do
        case generate_embedding(new_content) do
          {:ok, embedding} -> Map.put(attrs, :embedding, embedding)
          {:error, _reason} -> attrs
        end
      else
        attrs
      end

    memory
    |> UserMemory.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a memory.

  ## Examples

      iex> delete_memory(memory)
      {:ok, %UserMemory{}}

  """
  @spec delete_memory(UserMemory.t()) :: {:ok, UserMemory.t()} | {:error, Ecto.Changeset.t()}
  def delete_memory(%UserMemory{} = memory) do
    Repo.delete(memory)
  end

  @doc """
  Deletes a memory if it belongs to the specified user.

  ## Examples

      iex> delete_user_memory(memory_id, user_id)
      {:ok, %UserMemory{}}

      iex> delete_user_memory(memory_id, wrong_user_id)
      {:error, :not_found}

  """
  @spec delete_user_memory(binary(), binary()) ::
          {:ok, UserMemory.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_user_memory(memory_id, user_id) do
    case get_user_memory(memory_id, user_id) do
      nil -> {:error, :not_found}
      memory -> delete_memory(memory)
    end
  end

  @doc """
  Updates the last_accessed_at timestamp for retrieved memories.

  Called after memories are retrieved for context injection.

  ## Examples

      iex> touch_memories([memory_id_1, memory_id_2])
      {2, nil}

  """
  @spec touch_memories([binary()]) :: {non_neg_integer(), nil}
  def touch_memories(memory_ids) when is_list(memory_ids) and memory_ids != [] do
    now = DateTime.utc_now(:second)

    UserMemory
    |> where([m], m.id in ^memory_ids)
    |> Repo.update_all(set: [last_accessed_at: now])
  end

  def touch_memories([]), do: {0, nil}

  @doc """
  Returns the count of memories for a user.

  ## Examples

      iex> count_memories(user_id)
      42

  """
  @spec count_memories(binary()) :: non_neg_integer()
  def count_memories(user_id) do
    UserMemory
    |> where([m], m.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  # --- Conversation Summaries ---

  @doc """
  Returns all summaries for a conversation, ordered by message range.

  ## Examples

      iex> list_summaries(conversation_id)
      [%ConversationSummary{}, ...]

  """
  @spec list_summaries(binary()) :: [ConversationSummary.t()]
  def list_summaries(conversation_id) do
    ConversationSummary
    |> where([s], s.conversation_id == ^conversation_id)
    |> order_by([s], asc: s.message_range_start)
    |> Repo.all()
  end

  @doc """
  Gets the latest summary for a conversation.

  ## Examples

      iex> get_latest_summary(conversation_id)
      %ConversationSummary{}

      iex> get_latest_summary(conversation_id_without_summary)
      nil

  """
  @spec get_latest_summary(binary()) :: ConversationSummary.t() | nil
  def get_latest_summary(conversation_id) do
    ConversationSummary
    |> where([s], s.conversation_id == ^conversation_id)
    |> order_by([s], desc: s.message_range_end)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a conversation summary.

  ## Examples

      iex> create_summary(%{content: "...", conversation_id: id, message_range_start: 0, message_range_end: 10})
      {:ok, %ConversationSummary{}}

  """
  @spec create_summary(map()) :: {:ok, ConversationSummary.t()} | {:error, Ecto.Changeset.t()}
  def create_summary(attrs) do
    %ConversationSummary{}
    |> ConversationSummary.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes all summaries for a conversation.

  ## Examples

      iex> delete_summaries_for_conversation(conversation_id)
      {3, nil}

  """
  @spec delete_summaries_for_conversation(binary()) :: {non_neg_integer(), nil}
  def delete_summaries_for_conversation(conversation_id) do
    ConversationSummary
    |> where([s], s.conversation_id == ^conversation_id)
    |> Repo.delete_all()
  end

  # --- Helpers ---

  defp generate_embedding(nil), do: {:error, "Content is required for embedding"}
  defp generate_embedding(""), do: {:error, "Content cannot be empty"}

  defp generate_embedding(content) when is_binary(content) do
    case ollama_client().embed(content) do
      {:ok, embedding} -> {:ok, Pgvector.new(embedding)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ollama_client do
    Application.get_env(:chatbot, :ollama_client, Ollama)
  end

  @doc """
  Returns whether the memory system is enabled.

  ## Examples

      iex> enabled?()
      true

  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:chatbot, :memory, [])[:enabled] != false
  end

  @doc """
  Returns the configured maximum memories per user.

  ## Examples

      iex> max_memories_per_user()
      1000

  """
  @spec max_memories_per_user() :: pos_integer()
  def max_memories_per_user do
    Application.get_env(:chatbot, :memory, [])[:max_memories_per_user] || 1000
  end
end
