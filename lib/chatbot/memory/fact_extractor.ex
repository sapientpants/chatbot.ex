defmodule Chatbot.Memory.FactExtractor do
  @moduledoc """
  Extracts persistent facts from conversation exchanges using LLM.

  After each assistant response, this module analyzes the exchange and
  extracts any facts about the user that should be remembered for future
  conversations.

  ## Extraction Categories

  - `preference` - User preferences (likes, dislikes, preferred tools/methods)
  - `personal_info` - Personal information (name, location, occupation)
  - `skill` - Skills and expertise
  - `project` - Projects or work they're involved in
  - `context` - Important context that should be remembered
  """

  require Logger

  alias Chatbot.Memory
  alias Chatbot.Memory.Search
  alias Chatbot.LMStudio

  @extraction_prompt """
  Analyze this conversation exchange and extract any facts about the user that should be remembered for future conversations.

  Focus on:
  - Personal preferences (likes, dislikes, preferred tools/methods)
  - Personal information (name, location, occupation, etc.)
  - Skills and expertise they mention
  - Projects or work they're involved in
  - Important context they've shared

  Rules:
  - Only extract EXPLICIT facts stated by the user, not inferences
  - Skip trivial or temporary information
  - Each fact should be a standalone statement that makes sense without context
  - Rate confidence from 0.0 (uncertain) to 1.0 (explicitly stated)

  Respond with ONLY a JSON array (no markdown, no explanation):
  [{"content": "fact as a concise statement", "category": "preference|personal_info|skill|project|context", "confidence": 0.0-1.0}]

  If there are no facts worth remembering, respond with: []

  User message:
  """

  @doc """
  Extracts facts from a conversation exchange and stores them.

  This function should be called asynchronously after the assistant response
  is saved to avoid blocking the chat flow.

  ## Parameters

    * `user_id` - The user's ID
    * `user_message` - The user's message content
    * `assistant_message` - The assistant's response content
    * `source_message_id` - The ID of the assistant message (for reference)
    * `model` - The LLM model to use for extraction

  ## Returns

    * `:ok` on success (even if no facts were extracted)
    * `{:error, reason}` on failure

  """
  @spec extract_and_store(binary(), String.t(), String.t(), binary(), String.t()) ::
          :ok | {:error, term()}
  def extract_and_store(user_id, user_message, assistant_message, source_message_id, model) do
    if extraction_enabled?() do
      do_extract_and_store(user_id, user_message, assistant_message, source_message_id, model)
    else
      :ok
    end
  end

  defp do_extract_and_store(user_id, user_message, assistant_message, source_message_id, model) do
    prompt = build_prompt(user_message, assistant_message)

    messages = [
      %{
        role: "system",
        content: "You are a fact extraction assistant. Respond only with valid JSON arrays."
      },
      %{role: "user", content: prompt}
    ]

    case lm_studio_client().chat_completion(messages, model) do
      {:ok, %{"choices" => [%{"message" => %{"content" => response}} | _rest]}} ->
        process_extraction_response(response, user_id, source_message_id)

      {:ok, response} ->
        Logger.warning("Unexpected fact extraction response format: #{inspect(response)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.warning("Fact extraction failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Parses the LLM response and returns extracted facts.

  ## Examples

      iex> parse_response(~s|[{"content": "User prefers dark mode", "category": "preference", "confidence": 0.9}]|)
      {:ok, [%{content: "User prefers dark mode", category: "preference", confidence: 0.9}]}

      iex> parse_response("[]")
      {:ok, []}

      iex> parse_response("invalid json")
      {:error, :invalid_json}

  """
  @spec parse_response(String.t()) :: {:ok, [map()]} | {:error, :invalid_json}
  def parse_response(response) do
    # Try to find JSON array in the response
    response = String.trim(response)

    # Handle markdown code blocks
    json_str =
      case Regex.run(~r/```(?:json)?\s*(\[.*?\])\s*```/s, response) do
        [_full_match, json] -> json
        nil -> response
      end

    case Jason.decode(json_str) do
      {:ok, facts} when is_list(facts) ->
        parsed =
          facts
          |> Enum.filter(&valid_fact?/1)
          |> Enum.map(&normalize_fact/1)

        {:ok, parsed}

      {:ok, _other} ->
        {:error, :invalid_json}

      {:error, _reason} ->
        # Try to extract array from response
        case Regex.run(~r/\[.*\]/s, response) do
          [json] ->
            case Jason.decode(json) do
              {:ok, facts} when is_list(facts) ->
                parsed =
                  facts
                  |> Enum.filter(&valid_fact?/1)
                  |> Enum.map(&normalize_fact/1)

                {:ok, parsed}

              _other ->
                {:error, :invalid_json}
            end

          nil ->
            {:error, :invalid_json}
        end
    end
  end

  # Private functions

  defp build_prompt(user_message, assistant_message) do
    @extraction_prompt <>
      user_message <>
      "\n\nAssistant response:\n" <>
      assistant_message
  end

  defp process_extraction_response(response, user_id, source_message_id) do
    case parse_response(response) do
      {:ok, []} ->
        :ok

      {:ok, facts} ->
        store_facts(facts, user_id, source_message_id)

      {:error, :invalid_json} ->
        Logger.warning(
          "Failed to parse fact extraction response: #{String.slice(response, 0, 200)}"
        )

        :ok
    end
  end

  defp store_facts(facts, user_id, source_message_id) do
    # Check memory limit
    current_count = Memory.count_memories(user_id)
    max_count = Memory.max_memories_per_user()

    facts
    |> Enum.filter(fn fact -> fact.confidence >= 0.3 end)
    |> Enum.take(max_count - current_count)
    |> Enum.each(fn fact ->
      # Check for duplicates using semantic search
      unless similar_memory_exists?(user_id, fact.content) do
        Memory.create_memory(%{
          user_id: user_id,
          content: fact.content,
          category: fact.category,
          confidence: fact.confidence,
          source_message_id: source_message_id
        })
      end
    end)

    :ok
  end

  defp similar_memory_exists?(user_id, content) do
    case Search.search(user_id, content, limit: 1) do
      {:ok, [memory | _rest]} ->
        # Check if very similar (would need to compute similarity)
        # For now, do exact content check
        String.jaro_distance(String.downcase(memory.content), String.downcase(content)) > 0.85

      _other ->
        false
    end
  end

  defp valid_fact?(fact) do
    is_map(fact) and
      is_binary(fact["content"]) and
      String.length(fact["content"]) > 0 and
      fact["category"] in Memory.UserMemory.categories()
  end

  defp normalize_fact(fact) do
    %{
      content: fact["content"],
      category: fact["category"],
      confidence: normalize_confidence(fact["confidence"])
    }
  end

  defp normalize_confidence(nil), do: 0.5
  defp normalize_confidence(c) when is_number(c), do: max(0.0, min(1.0, c))
  defp normalize_confidence(_other), do: 0.5

  defp extraction_enabled? do
    Application.get_env(:chatbot, :memory, [])[:fact_extraction_enabled] != false
  end

  defp lm_studio_client do
    Application.get_env(:chatbot, :lm_studio_client, LMStudio)
  end
end
