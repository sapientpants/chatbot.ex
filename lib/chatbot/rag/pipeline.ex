defmodule Chatbot.RAG.Pipeline do
  @moduledoc """
  Orchestrates the full RAG retrieval pipeline.

  Pipeline stages:
  1. Query expansion (generate related queries)
  2. Hybrid search (semantic + keyword for each query)
  3. Combine and deduplicate results
  4. Rerank using LLM scoring
  5. Format as context string with footnote citations

  ## Citation Format

  The pipeline produces context with superscript footnote references:

      The API requires authentication¹ and supports rate limiting².

      ---
      Sources:
      [1] requirements.md (Authentication)
      [2] api-spec.md (Rate Limits)

  """

  alias Chatbot.Chat.AttachmentChunk
  alias Chatbot.RAG.ChunkSearch
  alias Chatbot.RAG.QueryExpander
  alias Chatbot.RAG.Reranker

  require Logger

  @doc """
  Executes the full RAG pipeline for a conversation.

  ## Parameters

    * `conversation_id` - The conversation to search within
    * `query` - The user's query
    * `opts` - Options
      * `:limit` - Maximum chunks to return (default: 5)
      * `:expand_queries` - Whether to expand queries (default: from config)
      * `:rerank` - Whether to rerank results (default: from config)

  ## Returns

    * `{:ok, chunks}` - List of relevant AttachmentChunk structs
    * `{:error, reason}` - If retrieval fails

  """
  @spec retrieve(binary(), String.t(), keyword()) ::
          {:ok, [AttachmentChunk.t()]} | {:error, term()}
  def retrieve(conversation_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, config(:retrieval_limit, 5))
    expand? = Keyword.get(opts, :expand_queries, config(:query_expansion_enabled, true))
    rerank? = Keyword.get(opts, :rerank, config(:reranking_enabled, true))

    Logger.debug("RAG pipeline: query=#{inspect(query)}, expand=#{expand?}, rerank=#{rerank?}")

    with {:ok, chunks} <- do_search(conversation_id, query, expand?, opts),
         {:ok, ranked} <- maybe_rerank(query, chunks, rerank?, opts) do
      {:ok, Enum.take(ranked, limit)}
    end
  end

  @doc """
  Retrieves and formats chunks as context for LLM with footnote citations.

  ## Parameters

    * `conversation_id` - The conversation to search within
    * `query` - The user's query
    * `opts` - Options (same as retrieve/3) plus:
      * `:token_budget` - Maximum tokens for context (default: 2000)

  ## Returns

    * `{:ok, context}` - Formatted context string with citations
    * `{:error, reason}` - If retrieval fails

  ## Example Output

      ## Retrieved from Attached Documents

      The following excerpts are relevant to your query. Use superscript numbers
      (e.g., "according to the docs¹") to cite sources in your response.

      ---

      ¹ **requirements.md** (Section: Authentication)
      Users must authenticate using API keys...

      ---

      ² **api-spec.md** (Section: Endpoints)
      The /users endpoint supports GET and POST...

      ---

      When responding, cite your sources using superscript numbers (¹, ², ³, etc.).

  """
  @spec retrieve_context(binary(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def retrieve_context(conversation_id, query, opts \\ []) do
    case retrieve_context_with_sources(conversation_id, query, opts) do
      {:ok, context, _sources} -> {:ok, context}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves context with source metadata for clickable citations.

  Returns both the formatted context string and a list of source metadata
  that can be stored with the message for rendering clickable footnotes.

  ## Parameters

  Same as `retrieve_context/3`.

  ## Returns

    * `{:ok, context, sources}` - Context string and source list
    * `{:error, reason}` - If retrieval fails

  Source format:
      [%{index: 1, filename: "doc.md", section: "Auth", content: "..."}]
  """
  @spec retrieve_context_with_sources(binary(), String.t(), keyword()) ::
          {:ok, String.t(), [map()]} | {:error, term()}
  def retrieve_context_with_sources(conversation_id, query, opts \\ []) do
    token_budget = Keyword.get(opts, :token_budget, config(:token_budget, 2000))

    case retrieve(conversation_id, query, opts) do
      {:ok, []} ->
        {:ok, "", []}

      {:ok, chunks} ->
        context = format_context_with_citations(chunks, token_budget)
        sources = chunks_to_sources(chunks)
        {:ok, context, sources}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if RAG is enabled and there are chunks for a conversation.

  ## Parameters

    * `conversation_id` - The conversation to check

  ## Returns

    * `true` if RAG is enabled and conversation has chunks
    * `false` otherwise

  """
  @spec available?(binary()) :: boolean()
  def available?(conversation_id) do
    if enabled?() do
      import Ecto.Query
      alias Chatbot.Repo

      count =
        AttachmentChunk
        |> where([c], c.conversation_id == ^conversation_id)
        |> select([_c], count())
        |> Repo.one()

      count > 0
    else
      false
    end
  end

  @doc """
  Returns whether RAG is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    config(:enabled, true)
  end

  # Private functions

  defp do_search(conversation_id, query, true = _expand?, opts) do
    # Expand queries and search with all of them
    case QueryExpander.expand_and_embed(query, opts) do
      {:ok, query_embeddings} ->
        ChunkSearch.search_multi(conversation_id, query_embeddings, opts)

      {:error, _reason} ->
        # Fall back to single query search
        ChunkSearch.search(conversation_id, query, opts)
    end
  end

  defp do_search(conversation_id, query, false = _expand?, opts) do
    ChunkSearch.search(conversation_id, query, opts)
  end

  defp maybe_rerank(query, chunks, true = _rerank?, opts) do
    Reranker.rerank_chunks(query, chunks, opts)
  end

  defp maybe_rerank(_query, chunks, false = _rerank?, _opts) do
    {:ok, chunks}
  end

  defp format_context_with_citations(chunks, token_budget) do
    # Estimate ~4 chars per token
    char_budget = token_budget * 4

    header = """
    ## Retrieved from Attached Documents

    The following excerpts are relevant to your query. Use superscript numbers (e.g., "according to the docs¹") to cite sources in your response.

    """

    footer = """

    ---

    When responding:
    1. Use superscript numbers (¹, ², ³, etc.) to cite sources inline
    2. At the end of your response, include a "References" section listing all cited sources in format:
       ## References
       ¹ filename.md - Section Name
       ² other-file.md - Section Name
    """

    header_footer_chars = String.length(header) + String.length(footer)
    available_chars = char_budget - header_footer_chars

    # Build numbered excerpts
    {excerpts, _remaining} =
      chunks
      |> Enum.with_index(1)
      |> Enum.reduce_while({[], available_chars}, fn {chunk, index}, {acc, remaining} ->
        excerpt = format_excerpt(chunk, index)
        excerpt_chars = String.length(excerpt)

        if excerpt_chars <= remaining do
          {:cont, {[excerpt | acc], remaining - excerpt_chars}}
        else
          # Try truncated version
          truncated = format_excerpt_truncated(chunk, index, remaining)

          if truncated do
            {:halt, {[truncated | acc], 0}}
          else
            {:halt, {acc, remaining}}
          end
        end
      end)

    if excerpts == [] do
      ""
    else
      body = excerpts |> Enum.reverse() |> Enum.join("\n\n---\n\n")
      header <> body <> footer
    end
  end

  defp format_excerpt(chunk, index) do
    header = build_excerpt_header(chunk, index)

    """
    #{header}
    #{chunk.content}
    """
  end

  defp format_excerpt_truncated(chunk, index, max_chars) do
    header = build_excerpt_header(chunk, index) <> "\n\n"
    header_chars = String.length(header)

    content_budget = max_chars - header_chars - 10

    if content_budget > 100 do
      truncated_content = String.slice(chunk.content, 0, content_budget) <> "..."
      header <> truncated_content
    else
      nil
    end
  end

  defp build_excerpt_header(chunk, index) do
    superscript = get_superscript(index)
    filename = get_filename(chunk)
    section = get_section(chunk)
    section_info = if section != "", do: " (Section: #{section})", else: ""

    "#{superscript} **#{filename}**#{section_info}"
  end

  defp get_superscript(index) when index >= 1 and index <= 20 do
    superscripts = %{
      1 => "¹",
      2 => "²",
      3 => "³",
      4 => "⁴",
      5 => "⁵",
      6 => "⁶",
      7 => "⁷",
      8 => "⁸",
      9 => "⁹",
      10 => "¹⁰",
      11 => "¹¹",
      12 => "¹²",
      13 => "¹³",
      14 => "¹⁴",
      15 => "¹⁵",
      16 => "¹⁶",
      17 => "¹⁷",
      18 => "¹⁸",
      19 => "¹⁹",
      20 => "²⁰"
    }

    Map.get(superscripts, index, "[#{index}]")
  end

  defp get_superscript(index), do: "[#{index}]"

  defp get_filename(chunk) do
    case chunk.metadata do
      %{"filename" => filename} when is_binary(filename) -> filename
      %{filename: filename} when is_binary(filename) -> filename
      _no_filename -> "Attachment"
    end
  end

  defp get_section(chunk) do
    case chunk.metadata do
      %{"section_path" => path} when is_binary(path) and path != "" -> path
      %{section_path: path} when is_binary(path) and path != "" -> path
      %{"headers" => [h | _rest]} when is_binary(h) -> h
      %{headers: [h | _rest]} when is_binary(h) -> h
      _no_section -> ""
    end
  end

  defp chunks_to_sources(chunks) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, index} ->
      %{
        "index" => index,
        "filename" => get_filename(chunk),
        "section" => get_section(chunk),
        "content" => chunk.content
      }
    end)
  end

  defp config(key, default) do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, key, default)
  end
end
