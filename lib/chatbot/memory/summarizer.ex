defmodule Chatbot.Memory.Summarizer do
  @moduledoc """
  Generates summaries for long conversations to preserve context within token budget.

  When conversations exceed the configured threshold, older messages are summarized
  to compress the context while retaining key information.

  ## Summary Strategy

  - Summaries cover ranges of messages (e.g., messages 0-30)
  - New summaries extend coverage, they don't replace existing ones
  - Summaries are generated incrementally as conversations grow
  """

  alias Chatbot.Chat
  alias Chatbot.LMStudio
  alias Chatbot.Memory

  require Logger

  @summarization_prompt """
  Summarize this conversation segment concisely, preserving:
  - Key decisions made
  - Important information shared
  - Questions asked and answered
  - Any commitments or action items

  Focus on facts and context that would be useful for continuing the conversation.
  Keep the summary under 300 words.

  Conversation:
  """

  @doc """
  Checks if a conversation needs summarization and generates one if needed.

  ## Parameters

    * `conversation_id` - The conversation to potentially summarize
    * `model` - The LLM model to use for summarization

  ## Returns

    * `{:ok, summary}` if a new summary was generated
    * `{:ok, nil}` if no summarization was needed
    * `{:error, reason}` on failure

  """
  @spec maybe_summarize(binary(), String.t()) ::
          {:ok, Memory.ConversationSummary.t() | nil} | {:error, term()}
  def maybe_summarize(conversation_id, model) do
    threshold = summarization_threshold()
    messages = Chat.list_messages(conversation_id)
    message_count = length(messages)

    if message_count >= threshold do
      existing_summary = Memory.get_latest_summary(conversation_id)
      covered_end = if existing_summary, do: existing_summary.message_range_end, else: 0

      # Check if we need to summarize more messages
      unsummarized_count = message_count - covered_end

      if unsummarized_count >= threshold do
        generate_summary(conversation_id, messages, covered_end, model)
      else
        {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  @doc """
  Generates a summary for a range of messages.

  ## Parameters

    * `conversation_id` - The conversation ID
    * `messages` - All messages in the conversation
    * `start_index` - First message index to summarize
    * `model` - The LLM model to use

  ## Returns

    * `{:ok, summary}` on success
    * `{:error, reason}` on failure

  """
  @spec generate_summary(binary(), [Chat.Message.t()], non_neg_integer(), String.t()) ::
          {:ok, Memory.ConversationSummary.t()} | {:error, term()}
  def generate_summary(conversation_id, messages, start_index, model) do
    # Summarize from start_index to near the end (leave recent messages unsummarized)
    threshold = summarization_threshold()
    end_index = length(messages) - div(threshold, 2)

    if end_index <= start_index do
      {:ok, nil}
    else
      messages_to_summarize = Enum.slice(messages, start_index, end_index - start_index)

      do_generate_summary(conversation_id, messages_to_summarize, start_index, end_index, model)
    end
  end

  defp do_generate_summary(conversation_id, messages, start_index, end_index, model) do
    conversation_text = format_messages_for_summary(messages)
    prompt = @summarization_prompt <> conversation_text

    llm_messages = [
      %{
        role: "system",
        content: "You are a helpful assistant that summarizes conversations concisely."
      },
      %{role: "user", content: prompt}
    ]

    case lm_studio_client().chat_completion(llm_messages, model) do
      {:ok, %{"choices" => [%{"message" => %{"content" => summary}} | _rest]}} ->
        Memory.create_summary(%{
          conversation_id: conversation_id,
          content: String.trim(summary),
          message_range_start: start_index,
          message_range_end: end_index,
          token_count: estimate_tokens(summary)
        })

      {:ok, response} ->
        Logger.warning("Unexpected summarization response: #{inspect(response)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.warning("Summarization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets combined summary text for a conversation.

  Combines all existing summaries into a single text block.

  ## Examples

      iex> get_combined_summary(conversation_id)
      "Previous conversation context:\\n..."

  """
  @spec get_combined_summary(binary()) :: String.t() | nil
  def get_combined_summary(conversation_id) do
    summaries = Memory.list_summaries(conversation_id)

    case summaries do
      [] ->
        nil

      summaries ->
        combined = Enum.map_join(summaries, "\n\n", & &1.content)
        "Previous conversation context:\n" <> combined
    end
  end

  # Private functions

  defp format_messages_for_summary(messages) do
    Enum.map_join(messages, "\n\n", fn msg ->
      role = String.capitalize(msg.role)
      "#{role}: #{msg.content}"
    end)
  end

  defp estimate_tokens(text) when is_binary(text) do
    # Approximate: 1 token ~= 4 characters for English
    div(String.length(text), 4)
  end

  defp summarization_threshold do
    Application.get_env(:chatbot, :memory, [])[:summarization_threshold] || 30
  end

  defp lm_studio_client do
    Application.get_env(:chatbot, :lm_studio_client, LMStudio)
  end
end
