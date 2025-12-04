defmodule Chatbot.Search.SearchUtils do
  @moduledoc """
  Shared utilities for hybrid search implementations.

  Provides common functions used by both Memory.Search and RAG.ChunkSearch
  including embedding retrieval, query building, and score fusion.
  """

  alias Chatbot.Memory.EmbeddingCache
  alias Chatbot.ProviderRouter

  # Reciprocal Rank Fusion (RRF) constant. Higher values reduce the impact of
  # rank differences. 60 is the standard value from the original RRF paper.
  @rrf_k 60

  @doc """
  Gets or computes an embedding for the given text, using cache.

  ## Returns

    * `{:ok, embedding}` - The Pgvector embedding
    * `{:error, reason}` - If embedding fails
  """
  @spec get_query_embedding(String.t()) :: {:ok, Pgvector.t()} | {:error, term()}
  def get_query_embedding(text) do
    result =
      EmbeddingCache.get_or_compute(text, fn t ->
        ProviderRouter.embed(t)
      end)

    case result do
      {:ok, embedding} -> {:ok, Pgvector.new(embedding)}
      error -> error
    end
  end

  @doc """
  Builds a PostgreSQL tsquery from text.

  Converts text to lowercase, splits on whitespace, removes non-word characters,
  and joins with AND operators.

  ## Examples

      iex> build_tsquery("Elixir programming")
      "elixir & programming"

  """
  @spec build_tsquery(String.t()) :: String.t()
  def build_tsquery(text) do
    text
    |> String.downcase()
    |> String.split(~r/\s+/)
    |> Enum.take(10)
    |> Enum.map(&String.replace(&1, ~r/[^\w]/, ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" & ")
  end

  @doc """
  Computes RRF scores for combining search results.

  Returns a list of `{id, score}` tuples.

  ## Parameters

    * `semantic_results` - Results from semantic search with :id and :rank
    * `keyword_results` - Results from keyword search with :id and :rank
    * `semantic_weight` - Weight for semantic results (0.0 to 1.0)
    * `keyword_weight` - Weight for keyword results (0.0 to 1.0)

  """
  @spec rrf_scores([map()], [map()], float(), float()) :: [{binary(), float()}]
  def rrf_scores(semantic_results, keyword_results, semantic_weight, keyword_weight) do
    # Build score map from semantic results
    semantic_scores =
      Enum.reduce(semantic_results, %{}, fn %{id: id, rank: rank}, acc ->
        score = semantic_weight / (@rrf_k + rank)
        Map.update(acc, id, score, &(&1 + score))
      end)

    # Add keyword scores and convert to list
    keyword_results
    |> Enum.reduce(semantic_scores, fn %{id: id, rank: rank}, acc ->
      score = keyword_weight / (@rrf_k + rank)
      Map.update(acc, id, score, &(&1 + score))
    end)
    |> Map.to_list()
  end

  @doc """
  Combines search results using Reciprocal Rank Fusion (RRF).

  RRF score = Σ(weight / (k + rank)) for each ranking

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
    scores = rrf_scores(semantic_results, keyword_results, semantic_weight, keyword_weight)

    scores
    |> Enum.sort_by(fn {_id, score} -> score end, :desc)
    |> Enum.map(fn {id, _score} -> id end)
  end
end
