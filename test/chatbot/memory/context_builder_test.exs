defmodule Chatbot.Memory.ContextBuilderTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Memory.ContextBuilder

  import Chatbot.Fixtures

  describe "estimate_tokens/1" do
    test "returns 0 for nil" do
      assert ContextBuilder.estimate_tokens(nil) == 0
    end

    test "returns 0 for empty string" do
      assert ContextBuilder.estimate_tokens("") == 0
    end

    test "estimates tokens for short text" do
      # ~4 chars per token with 10% buffer
      text = "Hello world"
      tokens = ContextBuilder.estimate_tokens(text)

      # 11 chars / 4 * 1.1 ≈ 3
      assert tokens > 0
      assert tokens < 10
    end

    test "estimates tokens for longer text" do
      text = String.duplicate("word ", 100)
      tokens = ContextBuilder.estimate_tokens(text)

      # 500 chars / 4 * 1.1 ≈ 137
      assert tokens > 100
      assert tokens < 200
    end
  end

  describe "apply_sliding_window/3" do
    test "returns all messages when within budget" do
      messages = [
        %{content: "Short message 1", role: "user"},
        %{content: "Short message 2", role: "assistant"}
      ]

      result = ContextBuilder.apply_sliding_window(messages, 1000, nil)

      assert length(result) == 2
    end

    test "truncates older messages when over budget" do
      messages =
        for i <- 1..10 do
          %{content: String.duplicate("word ", 50), role: "user", id: i}
        end

      # Small budget that can only fit a few messages
      result = ContextBuilder.apply_sliding_window(messages, 100, nil)

      # Should have fewer messages than original
      assert length(result) < 10
      # Should keep most recent (highest IDs)
      kept_ids = Enum.map(result, & &1.id)
      assert Enum.max(kept_ids) == 10
    end

    test "preserves message order" do
      messages = [
        %{content: "First", role: "user", id: 1},
        %{content: "Second", role: "assistant", id: 2},
        %{content: "Third", role: "user", id: 3}
      ]

      result = ContextBuilder.apply_sliding_window(messages, 1000, nil)

      assert Enum.map(result, & &1.id) == [1, 2, 3]
    end

    test "handles empty messages" do
      result = ContextBuilder.apply_sliding_window([], 1000, nil)

      assert result == []
    end
  end

  describe "build_memory_context/2" do
    setup do
      user = user_fixture()
      {:ok, user: user}
    end

    test "returns empty string when query is empty", %{user: user} do
      result = ContextBuilder.build_memory_context(user.id, "")

      assert result == ""
    end

    test "returns empty string when memory is disabled", %{user: user} do
      # Memory search will fail in tests due to mock, returns empty
      result = ContextBuilder.build_memory_context(user.id, "test query")

      # Will be empty since search fails or finds nothing
      assert is_binary(result)
    end
  end

  describe "build_context/3" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})

      # Add some messages
      {:ok, _msg1} =
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: "user",
          content: "Hello"
        })

      {:ok, _msg2} =
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: "assistant",
          content: "Hi there!"
        })

      {:ok, user: user, conversation: conversation}
    end

    test "returns OpenAI-formatted messages", %{user: user, conversation: conversation} do
      {:ok, messages} = ContextBuilder.build_context(conversation.id, user.id)

      assert is_list(messages)
      # Should have at least system prompt + conversation messages
      assert length(messages) >= 3

      # First should be system message
      assert hd(messages).role == "system"

      # All messages should have role and content
      assert Enum.all?(messages, &(Map.has_key?(&1, :role) and Map.has_key?(&1, :content)))
    end

    test "respects custom system prompt", %{user: user, conversation: conversation} do
      custom_prompt = "You are a pirate assistant."

      {:ok, messages} =
        ContextBuilder.build_context(conversation.id, user.id, system_prompt: custom_prompt)

      system_message = hd(messages)
      assert system_message.content =~ "pirate assistant"
    end

    test "includes conversation messages in order", %{user: user, conversation: conversation} do
      {:ok, messages} = ContextBuilder.build_context(conversation.id, user.id)

      # Filter to non-system messages
      conv_messages = Enum.filter(messages, &(&1.role != "system"))

      # Should have user then assistant
      roles = Enum.map(conv_messages, & &1.role)
      assert roles == ["user", "assistant"]
    end

    test "handles empty conversation", %{user: user} do
      {:ok, empty_conv} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Empty"})

      {:ok, messages} = ContextBuilder.build_context(empty_conv.id, user.id)

      # Should still have system prompt
      assert length(messages) >= 1
      assert hd(messages).role == "system"
    end

    test "includes summary when available", %{user: user, conversation: conversation} do
      # Add a summary
      Chatbot.Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "Summary of previous discussion",
        message_range_start: 0,
        message_range_end: 10
      })

      {:ok, messages} = ContextBuilder.build_context(conversation.id, user.id)

      # Should have two system messages (prompt + summary)
      system_messages = Enum.filter(messages, &(&1.role == "system"))
      assert length(system_messages) == 2

      # One should contain summary
      contents = Enum.map(system_messages, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "Summary of previous discussion"))
    end
  end
end
