defmodule Chatbot.Memory.Search do
  @moduledoc """
  Hybrid search implementation combining semantic (vector) and keyword (full-text) search.

  Uses Reciprocal Rank Fusion (RRF) to combine results from both search methods,
  providing better results than either method alone.

  ## How RRF Works

  RRF score = Σ(1 / (k + rank)) for each ranking

  Where k is a constant (default 60) that prevents high-ranked items from dominating.
  Results from both semantic and keyword search are ranked independently, then
  combined using RRF scores.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query

  alias Chatbot.Memory.EmbeddingCache
  alias Chatbot.Memory.UserMemory
  alias Chatbot.Ollama
  alias Chatbot.Repo

  @rrf_k 60

  @doc """
  Searches user memories using hybrid retrieval (semantic + keyword).

  ## Options

    * `:limit` - Maximum results to return (default: 5)
    * `:semantic_weight` - Weight for semantic results in RRF (default: from config or 0.6)
    * `:keyword_weight` - Weight for keyword results in RRF (default: from config or 0.4)
    * `:min_confidence` - Minimum confidence threshold (default: 0.0)
    * `:category` - Filter by category (optional)

  ## Examples

      iex> search(user_id, "What programming languages does the user know?")
      {:ok, [%UserMemory{content: "User is proficient in Elixir", ...}, ...]}

  """
  @spec search(binary(), String.t(), keyword()) :: {:ok, [UserMemory.t()]} | {:error, term()}
  def search(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, config(:retrieval_limit, 5))
    semantic_weight = Keyword.get(opts, :semantic_weight, config(:semantic_weight, 0.6))
    keyword_weight = Keyword.get(opts, :keyword_weight, config(:keyword_weight, 0.4))

    with {:ok, query_embedding} <- get_query_embedding(query_text) do
      # Run both searches
      semantic_results = semantic_search(user_id, query_embedding, opts)
      keyword_results = keyword_search(user_id, query_text, opts)

      # Combine with RRF
      fused_ids = rrf_fusion(semantic_results, keyword_results, semantic_weight, keyword_weight)

      # Fetch full records in fused order, limited
      memories = fetch_in_order(fused_ids, limit)

      {:ok, memories}
    end
  end

  @doc """
  Performs semantic-only search using vector similarity.

  ## Examples

      iex> semantic_search(user_id, query_embedding, limit: 10)
      [%{id: "...", distance: 0.15}, ...]

  """
  @spec semantic_search(binary(), Pgvector.Ecto.Vector.t() | [float()], keyword()) :: [map()]
  def semantic_search(user_id, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)
    category = Keyword.get(opts, :category)

    embedding =
      case query_embedding do
        %Pgvector{} -> query_embedding
        list when is_list(list) -> Pgvector.new(list)
      end

    query =
      from(m in UserMemory,
        where: m.user_id == ^user_id,
        where: m.confidence >= ^min_confidence,
        where: not is_nil(m.embedding),
        select: %{
          id: m.id,
          distance: cosine_distance(m.embedding, ^embedding)
        },
        order_by: cosine_distance(m.embedding, ^embedding),
        limit: ^limit
      )

    query
    |> maybe_filter_category(category)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

  @doc """
  Performs keyword-only search using PostgreSQL full-text search.

  ## Examples

      iex> keyword_search(user_id, "elixir programming", limit: 10)
      [%{id: "...", rank: 1}, ...]

  """
  @spec keyword_search(binary(), String.t(), keyword()) :: [map()]
  def keyword_search(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    min_confidence = Keyword.get(opts, :min_confidence, 0.0)
    category = Keyword.get(opts, :category)

    tsquery = build_tsquery(query_text)

    # Return empty if no valid search terms
    if tsquery == "" do
      []
    else
      query =
        from(m in UserMemory,
          where: m.user_id == ^user_id,
          where: m.confidence >= ^min_confidence,
          where: fragment("searchable @@ to_tsquery('english', ?)", ^tsquery),
          select: %{
            id: m.id,
            ts_rank: fragment("ts_rank_cd(searchable, to_tsquery('english', ?))", ^tsquery)
          },
          order_by: [desc: fragment("ts_rank_cd(searchable, to_tsquery('english', ?))", ^tsquery)],
          limit: ^limit
        )

      query
      |> maybe_filter_category(category)
      |> Repo.all()
      |> Enum.with_index(1)
      |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
    end
  end

  @doc """
  Combines search results using Reciprocal Rank Fusion.

  ## Parameters

    * `semantic_results` - Results from semantic search with :id and :rank
    * `keyword_results` - Results from keyword search with :id and :rank
    * `semantic_weight` - Weight for semantic results (0.0 to 1.0)
    * `keyword_weight` - Weight for keyword results (0.0 to 1.0)

  ## Returns

  List of IDs sorted by combined RRF score (highest first).
  """
  @spec rrf_fusion([map()], [map()], float(), float()) :: [binary()]
  def rrf_fusion(semantic_results, keyword_results, semantic_weight \\ 0.6, keyword_weight \\ 0.4) do
    # Build score map
    semantic_scores =
      Enum.reduce(semantic_results, %{}, fn %{id: id, rank: rank}, acc ->
        score = semantic_weight / (@rrf_k + rank)
        Map.update(acc, id, score, &(&1 + score))
      end)

    combined_scores =
      Enum.reduce(keyword_results, semantic_scores, fn %{id: id, rank: rank}, acc ->
        score = keyword_weight / (@rrf_k + rank)
        Map.update(acc, id, score, &(&1 + score))
      end)

    # Sort by score descending and return IDs
    combined_scores
    |> Enum.sort_by(fn {_id, score} -> score end, :desc)
    |> Enum.map(fn {id, _score} -> id end)
  end

  # Private functions

  defp get_query_embedding(text) do
    result =
      EmbeddingCache.get_or_compute(text, fn t ->
        ollama_client().embed(t)
      end)

    case result do
      {:ok, embedding} -> {:ok, Pgvector.new(embedding)}
      error -> error
    end
  end

  defp ollama_client do
    Application.get_env(:chatbot, :ollama_client, Ollama)
  end

  defp build_tsquery(text) do
    text
    |> String.downcase()
    |> String.split(~r/\s+/)
    |> Enum.take(10)
    |> Enum.map(&String.replace(&1, ~r/[^\w]/, ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" & ")
  end

  defp fetch_in_order([], _limit), do: []

  defp fetch_in_order(ids, limit) do
    ids_to_fetch = Enum.take(ids, limit)

    memories =
      UserMemory
      |> where([m], m.id in ^ids_to_fetch)
      |> Repo.all()

    # Reorder to match the fused order
    memory_map = Map.new(memories, fn m -> {m.id, m} end)

    ids_to_fetch
    |> Enum.map(fn id -> Map.get(memory_map, id) end)
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, category), do: where(query, [m], m.category == ^category)

  defp config(key, default) do
    Keyword.get(Application.get_env(:chatbot, :memory, []), key, default)
  end
end
