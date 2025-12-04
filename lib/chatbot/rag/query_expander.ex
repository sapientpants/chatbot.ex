defmodule Chatbot.RAG.QueryExpander do
  @moduledoc """
  Expands user queries into multiple related queries for improved retrieval.

  Uses LLM to generate semantically related queries that might match
  relevant content the original query would miss.

  ## Example

      {:ok, queries} = QueryExpander.expand("How do I authenticate?")
      # => {:ok, [
      #      "How do I authenticate?",
      #      "authentication methods",
      #      "login process",
      #      "API key setup"
      #    ]}

  """

  alias Chatbot.Memory.EmbeddingCache
  alias Chatbot.ModelCache
  alias Chatbot.ProviderRouter

  require Logger

  @expansion_prompt """
  Given the user query below, generate 2-3 alternative search queries that would help find relevant information. Focus on:
  - Synonyms and related terms
  - More specific variations
  - Broader conceptual queries

  Return ONLY the queries, one per line. No numbering, explanations, or extra text.

  User query: {{QUERY}}
  """

  @doc """
  Expands a query into multiple related queries.

  Returns the original query plus LLM-generated expansions.

  ## Parameters

    * `query` - The original user query
    * `opts` - Options
      * `:model` - Model to use for expansion (default: from settings)
      * `:max_queries` - Maximum expanded queries (default: 3)

  ## Returns

    * `{:ok, queries}` - List of queries starting with original
    * `{:error, reason}` - If expansion fails

  """
  @spec expand(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def expand(query, opts \\ []) do
    if expansion_enabled?() do
      do_expand(query, opts)
    else
      {:ok, [query]}
    end
  end

  @doc """
  Generates embeddings for all expanded queries.

  Uses caching to avoid redundant embedding calls.

  ## Parameters

    * `query` - The original user query
    * `opts` - Options passed to expand/2

  ## Returns

    * `{:ok, list}` - List of {query, embedding} tuples
    * `{:error, reason}` - If expansion or embedding fails

  """
  @spec expand_and_embed(String.t(), keyword()) ::
          {:ok, [{String.t(), [float()]}]} | {:error, term()}
  def expand_and_embed(query, opts \\ []) do
    with {:ok, queries} <- expand(query, opts) do
      embed_queries(queries)
    end
  end

  # Private functions

  defp do_expand(query, opts) do
    max_queries = Keyword.get(opts, :max_queries, config(:max_expanded_queries, 3))
    model = Keyword.get(opts, :model) || default_model()

    prompt = String.replace(@expansion_prompt, "{{QUERY}}", query)

    messages = [
      %{role: "user", content: prompt}
    ]

    case ProviderRouter.chat_completion(messages, model) do
      {:ok, response} ->
        expanded = parse_expansion_response(response, max_queries)
        # Always include original query first
        all_queries = [query | expanded] |> Enum.uniq() |> Enum.take(max_queries + 1)
        {:ok, all_queries}

      {:error, reason} ->
        Logger.warning("Query expansion failed: #{inspect(reason)}, using original query only")
        {:ok, [query]}
    end
  end

  defp parse_expansion_response(response, max_queries) do
    content =
      response
      |> get_in(["choices", Access.at(0), "message", "content"])
      |> Kernel.||("")

    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "-") end)
    |> Enum.map(&clean_query/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(max_queries)
  end

  defp clean_query(query) do
    query
    |> String.replace(~r/^\d+[\.\)]\s*/, "")
    |> String.replace(~r/^[-*]\s*/, "")
    |> String.trim()
  end

  defp embed_queries(queries) do
    results =
      Enum.map(queries, fn query ->
        result =
          EmbeddingCache.get_or_compute(query, fn q ->
            ProviderRouter.embed(q)
          end)

        case result do
          {:ok, embedding} -> {:ok, {query, embedding}}
          error -> error
        end
      end)

    errors = Enum.filter(results, &match?({:error, _reason}, &1))

    if errors == [] do
      embeddings = Enum.map(results, fn {:ok, pair} -> pair end)
      {:ok, embeddings}
    else
      {:error, elem(hd(errors), 1)}
    end
  end

  defp expansion_enabled? do
    config(:query_expansion_enabled, true)
  end

  defp default_model do
    case Chatbot.Settings.get("default_model") do
      nil -> first_available_model()
      model -> model
    end
  end

  defp first_available_model do
    case ModelCache.get_models() do
      {:ok, [first | _rest]} -> first["id"]
      _error -> nil
    end
  end

  defp config(key, default) do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, key, default)
  end
end
