defmodule Chatbot.RAG.Reranker do
  @moduledoc """
  Reranks search results using LLM-based relevance scoring.

  Takes initial retrieval results and reorders them based on
  relevance to the original query using batch LLM scoring.

  ## Example

      chunks = [%AttachmentChunk{content: "..."}, ...]
      {:ok, ranked} = Reranker.rerank("How do I authenticate?", chunks)
      # => {:ok, [{%AttachmentChunk{}, 9.0}, {%AttachmentChunk{}, 7.5}, ...]}

  """

  alias Chatbot.Chat.AttachmentChunk
  alias Chatbot.ProviderRouter

  require Logger

  @batch_rerank_prompt """
  Rate the relevance of each document chunk to the query. Return ONLY a JSON array of scores from 0-10.

  Query: {{QUERY}}

  Documents:
  {{DOCUMENTS}}

  Return a JSON array with exactly {{COUNT}} numbers (0-10 scale), one score per document in order.
  Example: [8, 5, 9, 3]

  Scores:
  """

  @doc """
  Reranks chunks by relevance to query using LLM scoring.

  ## Parameters

    * `query` - The original user query
    * `chunks` - List of AttachmentChunk structs to rerank
    * `opts` - Options
      * `:top_k` - Rerank top N chunks (default: 20)
      * `:return_k` - Return top N after reranking (default: 5)
      * `:model` - Model to use for reranking (default: from settings)

  ## Returns

    * `{:ok, ranked}` - List of {chunk, score} tuples sorted by score descending
    * `{:error, reason}` - If reranking fails

  """
  @spec rerank(String.t(), [AttachmentChunk.t()], keyword()) ::
          {:ok, [{AttachmentChunk.t(), float()}]} | {:error, term()}
  def rerank(query, chunks, opts \\ []) do
    if reranking_enabled?() and length(chunks) > 0 do
      do_rerank(query, chunks, opts)
    else
      # Return chunks with placeholder scores
      ranked =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {chunk, i} -> {chunk, 10.0 - i * 0.1} end)

      {:ok, ranked}
    end
  end

  @doc """
  Reranks chunks and returns only the chunks (without scores).

  Convenience function that extracts just the chunks from rerank/3.
  """
  @spec rerank_chunks(String.t(), [AttachmentChunk.t()], keyword()) ::
          {:ok, [AttachmentChunk.t()]} | {:error, term()}
  def rerank_chunks(query, chunks, opts \\ []) do
    case rerank(query, chunks, opts) do
      {:ok, ranked} ->
        {:ok, Enum.map(ranked, fn {chunk, _score} -> chunk end)}

      error ->
        error
    end
  end

  # Private functions

  defp do_rerank(query, chunks, opts) do
    top_k = Keyword.get(opts, :top_k, config(:rerank_top_k, 20))
    return_k = Keyword.get(opts, :return_k, config(:rerank_return_k, 5))
    model = Keyword.get(opts, :model) || default_model()

    # Only rerank top_k chunks
    chunks_to_rerank = Enum.take(chunks, top_k)

    case batch_rerank(query, chunks_to_rerank, model) do
      {:ok, scored} ->
        # Sort by score descending and take return_k
        ranked =
          scored
          |> Enum.sort_by(fn {_chunk, score} -> score end, :desc)
          |> Enum.take(return_k)

        {:ok, ranked}

      {:error, reason} ->
        Logger.warning(
          "Batch reranking failed: #{inspect(reason)}, falling back to original order"
        )

        # Fallback: return original order with placeholder scores
        ranked =
          chunks_to_rerank
          |> Enum.take(return_k)
          |> Enum.with_index()
          |> Enum.map(fn {chunk, i} -> {chunk, 10.0 - i * 0.1} end)

        {:ok, ranked}
    end
  end

  defp batch_rerank(query, chunks, model) do
    # Format documents for batch scoring
    documents =
      Enum.map_join(Enum.with_index(chunks, 1), "\n\n", fn {chunk, i} ->
        content = truncate_content(chunk.content, 500)
        "[#{i}] #{content}"
      end)

    prompt =
      @batch_rerank_prompt
      |> String.replace("{{QUERY}}", query)
      |> String.replace("{{DOCUMENTS}}", documents)
      |> String.replace("{{COUNT}}", Integer.to_string(length(chunks)))

    messages = [%{role: "user", content: prompt}]

    case ProviderRouter.chat_completion(messages, model) do
      {:ok, response} ->
        parse_batch_scores(response, chunks)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_batch_scores(response, chunks) do
    content =
      response
      |> get_in(["choices", Access.at(0), "message", "content"])
      |> Kernel.||("")
      |> String.trim()

    # Try to parse as JSON array
    case parse_json_array(content) do
      {:ok, scores} when length(scores) == length(chunks) ->
        scored = Enum.zip(chunks, scores)
        {:ok, scored}

      {:ok, scores} ->
        # Scores don't match chunk count - pad or truncate
        Logger.warning("Score count mismatch: got #{length(scores)}, expected #{length(chunks)}")
        padded_scores = pad_scores(scores, length(chunks))
        scored = Enum.zip(chunks, padded_scores)
        {:ok, scored}

      {:error, _json_error} ->
        # Try to extract individual numbers
        case extract_numbers(content, length(chunks)) do
          scores when length(scores) == length(chunks) ->
            scored = Enum.zip(chunks, scores)
            {:ok, scored}

          _partial_scores ->
            {:error, "Failed to parse reranking scores"}
        end
    end
  end

  defp parse_json_array(content) do
    # Find JSON array in content
    case Regex.run(~r/\[[\d\s,\.]+\]/, content) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, scores} when is_list(scores) ->
            normalized = Enum.map(scores, &normalize_score/1)
            {:ok, normalized}

          _decode_error ->
            {:error, :invalid_json}
        end

      _no_match ->
        {:error, :no_array_found}
    end
  end

  defp extract_numbers(content, expected_count) do
    content
    |> String.split(~r/[\s,\[\]]+/)
    |> Enum.map(&parse_number/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(expected_count)
  end

  defp parse_number(str) do
    case Float.parse(str) do
      {num, _rest} -> normalize_score(num)
      :error -> nil
    end
  end

  defp normalize_score(score) when is_number(score) do
    score
    |> max(0.0)
    |> min(10.0)
  end

  defp normalize_score(_non_number), do: 5.0

  defp pad_scores(scores, target_length) do
    current_length = length(scores)

    if current_length >= target_length do
      Enum.take(scores, target_length)
    else
      # Pad with average or 5.0 (guard against division by zero)
      avg = if current_length > 0, do: Enum.sum(scores) / current_length, else: 5.0
      scores ++ List.duplicate(avg, target_length - current_length)
    end
  end

  defp truncate_content(content, max_chars) do
    if String.length(content) > max_chars do
      String.slice(content, 0, max_chars) <> "..."
    else
      content
    end
  end

  defp reranking_enabled? do
    config(:reranking_enabled, true)
  end

  defp default_model do
    Chatbot.Settings.get("default_model") || "ollama/llama3"
  end

  defp config(key, default) do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, key, default)
  end
end
