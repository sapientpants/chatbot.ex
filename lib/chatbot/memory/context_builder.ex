defmodule Chatbot.Memory.ContextBuilder do
  @moduledoc """
  Builds conversation context for LLM prompts with memory integration.

  Assembles the context by:
  1. Retrieving relevant user memories based on the current query
  2. Including conversation summaries if the conversation is long
  3. Applying a sliding window to recent messages to fit within token budget

  ## Token Budget Allocation

  Default budget: 4000 tokens
  - System prompt + memories: ~1300 tokens
  - Conversation summary: ~400 tokens (if needed)
  - Recent messages: remaining tokens

  """

  alias Chatbot.Chat
  alias Chatbot.Memory
  alias Chatbot.Memory.Search
  alias Chatbot.Memory.Summarizer

  @default_token_budget 4000

  # Token estimation constants:
  # - Approximate 4 characters per token for English text
  # - 10% buffer for encoding overhead and tokenization variance
  # - 10 tokens per message for role/formatting overhead
  # - 100 token buffer subtracted from budget for response generation
  @chars_per_token 4
  @token_estimate_buffer 1.1
  @message_overhead_tokens 10
  @response_buffer_tokens 100

  @base_system_prompt """
  You are a helpful AI assistant. Be concise, accurate, and helpful.
  """

  @doc """
  Builds the complete context for an LLM API call.

  ## Parameters

    * `conversation_id` - The current conversation ID
    * `user_id` - The user's ID
    * `opts` - Options including:
      * `:current_query` - The user's current message (for memory retrieval)
      * `:system_prompt` - Custom system prompt (optional)
      * `:token_budget` - Custom token budget (optional)
      * `:model` - Model name for potential summarization

  ## Returns

    * `{:ok, messages}` - List of messages in OpenAI format
    * `{:error, reason}` - On failure

  ## Example Response Format

      {:ok, [
        %{role: "system", content: "You are helpful...\\n\\nUser context: ..."},
        %{role: "user", content: "Earlier message"},
        %{role: "assistant", content: "Earlier response"},
        %{role: "user", content: "Current message"}
      ]}

  """
  @spec build_context(binary(), binary(), keyword()) :: {:ok, [map()]}
  def build_context(conversation_id, user_id, opts \\ []) do
    current_query = Keyword.get(opts, :current_query, "")
    custom_system_prompt = Keyword.get(opts, :system_prompt)
    token_budget = Keyword.get(opts, :token_budget, config(:token_budget, @default_token_budget))

    # Build system prompt with memory context
    memory_context = build_memory_context(user_id, current_query)
    system_prompt = build_system_prompt(custom_system_prompt, memory_context)
    system_tokens = estimate_tokens(system_prompt)

    # Get conversation summary if available
    summary_context = Summarizer.get_combined_summary(conversation_id)
    summary_tokens = if summary_context, do: estimate_tokens(summary_context), else: 0

    # Calculate remaining budget for messages
    remaining_budget = token_budget - system_tokens - summary_tokens - @response_buffer_tokens

    # Get messages with sliding window
    messages = Chat.list_messages(conversation_id)
    recent_messages = apply_sliding_window(messages, remaining_budget, summary_context)

    # Build final message list
    openai_messages = build_openai_messages(system_prompt, summary_context, recent_messages)

    # Touch accessed memories to track usage
    touch_accessed_memories(user_id, current_query)

    {:ok, openai_messages}
  end

  @doc """
  Builds memory context string for injection into system prompt.

  ## Parameters

    * `user_id` - The user's ID
    * `current_query` - The current message for relevance matching

  ## Returns

  A formatted string with relevant memories, or empty string if none found.
  """
  @spec build_memory_context(binary(), String.t()) :: String.t()
  def build_memory_context(user_id, current_query) do
    if Memory.enabled?() and current_query != "" do
      case Search.search(user_id, current_query, limit: config(:retrieval_limit, 5)) do
        {:ok, []} ->
          ""

        {:ok, memories} ->
          facts = Enum.map_join(memories, "\n", &format_memory/1)
          "\n\nRelevant information about this user:\n#{facts}"

        {:error, _reason} ->
          ""
      end
    else
      ""
    end
  end

  @doc """
  Applies a sliding window to messages to fit within token budget.

  Always includes the most recent messages. If there's a summary,
  older messages are assumed to be covered by it.

  ## Parameters

    * `messages` - All messages in the conversation
    * `budget` - Token budget for messages
    * `summary_context` - Summary text if available (affects starting point)

  ## Returns

  List of messages that fit within the budget, preserving most recent.
  """
  @spec apply_sliding_window([Chat.Message.t()], non_neg_integer(), String.t() | nil) ::
          [Chat.Message.t()]
  def apply_sliding_window(messages, budget, _summary_context) do
    # Work backwards from most recent, accumulating until budget is exceeded
    messages
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn msg, {acc, tokens} ->
      msg_tokens = estimate_tokens(msg.content) + @message_overhead_tokens

      if tokens + msg_tokens <= budget do
        {:cont, {[msg | acc], tokens + msg_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
  end

  @doc """
  Estimates token count for text.

  Uses a simple heuristic: ~4 characters per token for English text.
  """
  @spec estimate_tokens(String.t() | nil) :: non_neg_integer()
  def estimate_tokens(nil), do: 0

  def estimate_tokens(text) when is_binary(text) do
    trunc(String.length(text) / @chars_per_token * @token_estimate_buffer)
  end

  # Private functions

  defp build_system_prompt(nil, memory_context) do
    @base_system_prompt <> memory_context
  end

  defp build_system_prompt(custom_prompt, memory_context) do
    custom_prompt <> memory_context
  end

  defp build_openai_messages(system_prompt, nil, messages) do
    [%{role: "system", content: system_prompt} | format_messages(messages)]
  end

  defp build_openai_messages(system_prompt, summary_context, messages) do
    # Insert summary as a system message after the main system prompt
    [
      %{role: "system", content: system_prompt},
      %{role: "system", content: summary_context}
      | format_messages(messages)
    ]
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
  end

  defp format_memory(memory) do
    category_label =
      case memory.category do
        "preference" -> "Preference"
        "personal_info" -> "About user"
        "skill" -> "Skill"
        "project" -> "Project"
        "context" -> "Context"
        _other -> "Note"
      end

    "- [#{category_label}] #{memory.content}"
  end

  defp touch_accessed_memories(user_id, query) do
    # Touch memories that were accessed (best effort, async)
    Task.start(fn ->
      case Search.search(user_id, query, limit: config(:retrieval_limit, 5)) do
        {:ok, memories} ->
          memory_ids = Enum.map(memories, & &1.id)
          Memory.touch_memories(memory_ids)

        _error ->
          :ok
      end
    end)
  end

  defp config(key, default) do
    Keyword.get(Application.get_env(:chatbot, :memory, []), key, default)
  end
end
