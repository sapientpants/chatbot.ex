defmodule Chatbot.RAG.ChunkSearch do
  @moduledoc """
  Hybrid search implementation for attachment chunks.

  Adapts the pattern from Memory.Search for chunk-specific retrieval
  with conversation-scoped filtering. Combines semantic (vector) and
  keyword (full-text) search using Reciprocal Rank Fusion (RRF).

  ## How RRF Works

  RRF score = Σ(1 / (k + rank)) for each ranking

  Where k is a constant (default 60) that prevents high-ranked items from dominating.
  Results from both semantic and keyword search are ranked independently, then
  combined using RRF scores.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query

  alias Chatbot.Chat.AttachmentChunk
  alias Chatbot.Repo
  alias Chatbot.Search.SearchUtils

  @doc """
  Searches attachment chunks using hybrid retrieval (semantic + keyword).

  Scoped to a single conversation for isolation between users.

  ## Parameters

    * `conversation_id` - The conversation to search within
    * `query_text` - The search query
    * `opts` - Options
      * `:limit` - Maximum results (default: 10)
      * `:semantic_weight` - Weight for semantic results (default: 0.6)
      * `:keyword_weight` - Weight for keyword results (default: 0.4)
      * `:attachment_ids` - Optional list to filter specific attachments
      * `:deduplicate` - Whether to deduplicate results (default: true)

  ## Returns

    * `{:ok, chunks}` - List of AttachmentChunk structs ordered by relevance
    * `{:error, reason}` - If search fails

  """
  @spec search(binary(), String.t(), keyword()) ::
          {:ok, [AttachmentChunk.t()]} | {:error, term()}
  def search(conversation_id, query_text, opts \\ []) do
    {limit, semantic_weight, keyword_weight} = parse_weights(opts)
    deduplicate? = Keyword.get(opts, :deduplicate, true)

    with {:ok, query_embedding} <- SearchUtils.get_query_embedding(query_text) do
      # Run both searches
      semantic_results = semantic_search(conversation_id, query_embedding, opts)
      keyword_results = keyword_search(conversation_id, query_text, opts)

      # Combine with RRF
      fused_ids =
        SearchUtils.rrf_fusion(semantic_results, keyword_results, semantic_weight, keyword_weight)

      # Fetch 2x limit to account for deduplication removing some results
      fetched_chunks = fetch_in_order(fused_ids, limit * 2)

      # Deduplicate if enabled
      final_chunks = if deduplicate?, do: deduplicate(fetched_chunks), else: fetched_chunks

      {:ok, Enum.take(final_chunks, limit)}
    end
  end

  @doc """
  Searches with multiple query embeddings (for query expansion).

  Runs hybrid search for each query and combines all results.

  ## Parameters

    * `conversation_id` - The conversation to search within
    * `query_embeddings` - List of {query_text, embedding} tuples
    * `opts` - Same options as search/3

  ## Returns

    * `{:ok, chunks}` - Combined and deduplicated results
    * `{:error, reason}` - If search fails

  """
  @spec search_multi(binary(), [{String.t(), [float()]}], keyword()) ::
          {:ok, [AttachmentChunk.t()]} | {:error, term()}
  def search_multi(conversation_id, query_embeddings, opts \\ []) do
    {limit, semantic_weight, keyword_weight} = parse_weights(opts)

    # Collect results from all queries
    all_results =
      Enum.flat_map(query_embeddings, fn {query_text, embedding} ->
        pgvector_embedding = Pgvector.new(embedding)
        semantic_results = semantic_search(conversation_id, pgvector_embedding, opts)
        keyword_results = keyword_search(conversation_id, query_text, opts)

        # Get RRF scores for this query
        SearchUtils.rrf_scores(semantic_results, keyword_results, semantic_weight, keyword_weight)
      end)

    # Aggregate scores by chunk ID
    aggregated =
      all_results
      |> Enum.group_by(fn {id, _score} -> id end)
      |> Enum.map(fn {id, scores} ->
        total_score = Enum.sum(Enum.map(scores, &elem(&1, 1)))
        {id, total_score}
      end)
      |> Enum.sort_by(fn {_id, score} -> score end, :desc)
      |> Enum.map(fn {id, _score} -> id end)

    # Fetch and deduplicate
    fetched_chunks = fetch_in_order(aggregated, limit * 2)
    final_chunks = deduplicate(fetched_chunks)

    {:ok, Enum.take(final_chunks, limit)}
  end

  @doc """
  Performs semantic-only search using vector similarity.

  ## Parameters

    * `conversation_id` - The conversation to search within
    * `query_embedding` - The query embedding vector
    * `opts` - Options including `:limit` and `:attachment_ids`

  ## Returns

  List of maps with :id, :distance, and :rank keys.
  """
  @spec semantic_search(binary(), Pgvector.Ecto.Vector.t() | [float()], keyword()) :: [map()]
  def semantic_search(conversation_id, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    attachment_ids = Keyword.get(opts, :attachment_ids)

    embedding =
      case query_embedding do
        %Pgvector{} -> query_embedding
        list when is_list(list) -> Pgvector.new(list)
      end

    query =
      from(c in AttachmentChunk,
        where: c.conversation_id == ^conversation_id,
        where: not is_nil(c.embedding),
        select: %{
          id: c.id,
          distance: cosine_distance(c.embedding, ^embedding)
        },
        order_by: cosine_distance(c.embedding, ^embedding),
        limit: ^limit
      )

    query
    |> maybe_filter_attachments(attachment_ids)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

  @doc """
  Performs keyword-only search using PostgreSQL full-text search.

  ## Parameters

    * `conversation_id` - The conversation to search within
    * `query_text` - The search query
    * `opts` - Options including `:limit` and `:attachment_ids`

  ## Returns

  List of maps with :id, :ts_rank, and :rank keys.
  """
  @spec keyword_search(binary(), String.t(), keyword()) :: [map()]
  def keyword_search(conversation_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    attachment_ids = Keyword.get(opts, :attachment_ids)

    tsquery = SearchUtils.build_tsquery(query_text)

    # Return empty if no valid search terms
    if tsquery == "" do
      []
    else
      query =
        from(c in AttachmentChunk,
          where: c.conversation_id == ^conversation_id,
          where: fragment("searchable @@ to_tsquery('english', ?)", ^tsquery),
          select: %{
            id: c.id,
            ts_rank: fragment("ts_rank_cd(searchable, to_tsquery('english', ?))", ^tsquery)
          },
          order_by: [desc: fragment("ts_rank_cd(searchable, to_tsquery('english', ?))", ^tsquery)],
          limit: ^limit
        )

      query
      |> maybe_filter_attachments(attachment_ids)
      |> Repo.all()
      |> Enum.with_index(1)
      |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
    end
  end

  @doc """
  Combines search results using Reciprocal Rank Fusion.

  See `Chatbot.Search.SearchUtils.rrf_fusion/4` for details.
  """
  @spec rrf_fusion([map()], [map()], float(), float()) :: [binary()]
  def rrf_fusion(semantic_results, keyword_results, semantic_weight \\ 0.6, keyword_weight \\ 0.4) do
    SearchUtils.rrf_fusion(semantic_results, keyword_results, semantic_weight, keyword_weight)
  end

  @doc """
  Deduplicates chunks by content_hash, keeping the first occurrence.
  """
  @spec deduplicate([AttachmentChunk.t()]) :: [AttachmentChunk.t()]
  def deduplicate(chunks) do
    Enum.uniq_by(chunks, & &1.content_hash)
  end

  # Private functions

  defp fetch_in_order([], _limit), do: []

  defp fetch_in_order(ids, limit) do
    ids_to_fetch = Enum.take(ids, limit)

    chunks =
      AttachmentChunk
      |> where([c], c.id in ^ids_to_fetch)
      |> Repo.all()

    # Reorder to match the fused order
    chunk_map = Map.new(chunks, fn c -> {c.id, c} end)

    ids_to_fetch
    |> Enum.map(fn id -> Map.get(chunk_map, id) end)
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_filter_attachments(query, nil), do: query

  defp maybe_filter_attachments(query, attachment_ids) when is_list(attachment_ids) do
    where(query, [c], c.attachment_id in ^attachment_ids)
  end

  defp parse_weights(opts) do
    limit = Keyword.get(opts, :limit, config(:retrieval_limit, 10))
    semantic_weight = Keyword.get(opts, :semantic_weight, config(:semantic_weight, 0.6))
    keyword_weight = Keyword.get(opts, :keyword_weight, config(:keyword_weight, 0.4))
    {limit, semantic_weight, keyword_weight}
  end

  defp config(key, default) do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, key, default)
  end
end
