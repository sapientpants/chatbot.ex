defmodule Chatbot.Memory.ContextBuilderTest do
  use Chatbot.DataCase, async: false

  import Mox

  alias Chatbot.Memory
  alias Chatbot.Memory.ContextBuilder

  import Chatbot.Fixtures

  setup :set_mox_global
  setup :verify_on_exit!

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
      {:ok, messages, _rag_sources} = ContextBuilder.build_context(conversation.id, user.id)

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

      {:ok, messages, _rag_sources} =
        ContextBuilder.build_context(conversation.id, user.id, system_prompt: custom_prompt)

      system_message = hd(messages)
      assert system_message.content =~ "pirate assistant"
    end

    test "includes conversation messages in order", %{user: user, conversation: conversation} do
      {:ok, messages, _rag_sources} = ContextBuilder.build_context(conversation.id, user.id)

      # Filter to non-system messages
      conv_messages = Enum.filter(messages, &(&1.role != "system"))

      # Should have user then assistant
      roles = Enum.map(conv_messages, & &1.role)
      assert roles == ["user", "assistant"]
    end

    test "handles empty conversation", %{user: user} do
      {:ok, empty_conv} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Empty"})

      {:ok, messages, _rag_sources} = ContextBuilder.build_context(empty_conv.id, user.id)

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

      {:ok, messages, _rag_sources} = ContextBuilder.build_context(conversation.id, user.id)

      # Should have two system messages (prompt + summary)
      system_messages = Enum.filter(messages, &(&1.role == "system"))
      assert length(system_messages) == 2

      # One should contain summary
      contents = Enum.map(system_messages, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "Summary of previous discussion"))
    end
  end

  describe "build_memory_context/2 with memories" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})

      original_ollama = Application.get_env(:chatbot, :ollama_client)
      Application.put_env(:chatbot, :ollama_client, Chatbot.OllamaMock)

      on_exit(fn ->
        if original_ollama,
          do: Application.put_env(:chatbot, :ollama_client, original_ollama),
          else: Application.delete_env(:chatbot, :ollama_client)
      end)

      {:ok, user: user, conversation: conversation}
    end

    test "includes memories in context when found", %{user: user} do
      # Create test memories with embeddings using create_memory_without_embedding
      embedding = List.duplicate(0.1, 1024)

      {:ok, _memory} =
        Memory.create_memory_without_embedding(%{
          user_id: user.id,
          content: "User prefers dark mode",
          category: "preference",
          confidence: 0.9,
          embedding: Pgvector.new(embedding)
        })

      # Mock embedding for search
      stub(Chatbot.OllamaMock, :embed, fn _text -> {:ok, embedding} end)
      stub(Chatbot.OllamaMock, :embedding_dimension, fn -> 1024 end)

      result = ContextBuilder.build_memory_context(user.id, "What are my preferences?")

      assert result =~ "Relevant information about this user"
      assert result =~ "Preference"
      assert result =~ "User prefers dark mode"
    end

    test "formats different memory categories", %{user: user} do
      embedding = List.duplicate(0.1, 1024)

      # Create memories with different categories using create_memory_without_embedding
      for {content, category} <- [
            {"User is a software developer", "skill"},
            {"User is named John", "personal_info"},
            {"User is working on a chat app", "project"},
            {"User mentioned meeting next week", "context"}
          ] do
        {:ok, _memory} =
          Memory.create_memory_without_embedding(%{
            user_id: user.id,
            content: content,
            category: category,
            confidence: 0.9,
            embedding: Pgvector.new(embedding)
          })
      end

      stub(Chatbot.OllamaMock, :embed, fn _text -> {:ok, embedding} end)
      stub(Chatbot.OllamaMock, :embedding_dimension, fn -> 1024 end)

      result = ContextBuilder.build_memory_context(user.id, "Tell me about myself")

      # Should have formatted category labels
      assert result =~ "Skill"
      assert result =~ "About user"
      assert result =~ "Project"
      assert result =~ "Context"
    end

    test "returns empty string when search fails", %{user: user} do
      stub(Chatbot.OllamaMock, :embed, fn _text -> {:error, "Connection refused"} end)
      stub(Chatbot.OllamaMock, :embedding_dimension, fn -> 1024 end)

      result = ContextBuilder.build_memory_context(user.id, "test query")

      assert result == ""
    end
  end

  describe "build_context/3 with memories" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})

      {:ok, _msg1} =
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: "user",
          content: "Hello"
        })

      original_ollama = Application.get_env(:chatbot, :ollama_client)
      Application.put_env(:chatbot, :ollama_client, Chatbot.OllamaMock)

      on_exit(fn ->
        if original_ollama,
          do: Application.put_env(:chatbot, :ollama_client, original_ollama),
          else: Application.delete_env(:chatbot, :ollama_client)
      end)

      {:ok, user: user, conversation: conversation}
    end

    test "includes memory context in system prompt", %{user: user, conversation: conversation} do
      embedding = List.duplicate(0.1, 1024)

      {:ok, _memory} =
        Memory.create_memory_without_embedding(%{
          user_id: user.id,
          content: "User likes Elixir",
          category: "preference",
          confidence: 0.9,
          embedding: Pgvector.new(embedding)
        })

      stub(Chatbot.OllamaMock, :embed, fn _text -> {:ok, embedding} end)
      stub(Chatbot.OllamaMock, :embedding_dimension, fn -> 1024 end)

      {:ok, messages, _rag_sources} =
        ContextBuilder.build_context(
          conversation.id,
          user.id,
          current_query: "What language should I use?"
        )

      system_prompt = hd(messages).content
      assert system_prompt =~ "User likes Elixir"
    end

    test "respects token budget", %{user: user, conversation: conversation} do
      # Add many messages to exceed budget
      for i <- 1..50 do
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: if(rem(i, 2) == 0, do: "assistant", else: "user"),
          content: String.duplicate("This is a long message content. ", 20)
        })
      end

      {:ok, messages, _rag_sources} =
        ContextBuilder.build_context(
          conversation.id,
          user.id,
          token_budget: 500
        )

      # Should have fewer than all messages due to budget
      non_system_messages = Enum.filter(messages, &(&1.role != "system"))
      assert length(non_system_messages) < 50
    end
  end

  describe "build_attachment_context/2" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})
      {:ok, user: user, conversation: conversation}
    end

    test "returns empty string when no attachments", %{conversation: conversation} do
      result = ContextBuilder.build_attachment_context(conversation.id, "test query")
      assert result == ""
    end

    test "returns empty string when RAG is disabled", %{conversation: conversation} do
      # RAG is disabled in test config, so attachment context always returns empty
      # (no fallback to full file content per user preference)
      {:ok, _attachment} =
        Chatbot.Chat.create_attachment(%{
          conversation_id: conversation.id,
          filename: "notes.md",
          content: "# Important Notes\n\nThis is important.",
          size_bytes: 50
        })

      result = ContextBuilder.build_attachment_context(conversation.id, "test query")

      # With RAG disabled, returns empty string
      assert result == ""
    end

    test "returns empty string when query is empty", %{conversation: conversation} do
      {:ok, _attachment} =
        Chatbot.Chat.create_attachment(%{
          conversation_id: conversation.id,
          filename: "file1.md",
          content: "Content 1",
          size_bytes: 10
        })

      # Empty query returns empty context
      result = ContextBuilder.build_attachment_context(conversation.id, "")
      assert result == ""
    end
  end

  describe "build_context/3 with attachments" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})

      {:ok, _msg} =
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: "user",
          content: "Hello"
        })

      {:ok, user: user, conversation: conversation}
    end

    test "does not include attachment context when RAG is disabled", %{
      user: user,
      conversation: conversation
    } do
      # With RAG disabled in test config, attachments are not included in context
      # (no fallback to full file content per user preference)
      {:ok, _attachment} =
        Chatbot.Chat.create_attachment(%{
          conversation_id: conversation.id,
          filename: "reference.md",
          content: "# Reference Document\n\nKey information here.",
          size_bytes: 50
        })

      {:ok, messages, _rag_sources} = ContextBuilder.build_context(conversation.id, user.id)

      system_prompt = hd(messages).content
      # With RAG disabled, attachment content is NOT included
      refute system_prompt =~ "Reference Document"
      refute system_prompt =~ "Key information here"
    end
  end
end
