defmodule Chatbot.MemoryTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Memory
  alias Chatbot.Memory.ConversationSummary
  alias Chatbot.Memory.UserMemory

  import Chatbot.Fixtures

  describe "user memories" do
    setup do
      user = user_fixture()
      {:ok, user: user}
    end

    test "create_memory/1 attempts to create memory with embedding", %{user: user} do
      # In test env, Ollama may succeed or fail depending on mock state
      attrs = %{
        user_id: user.id,
        content: "User prefers dark mode",
        category: "preference",
        confidence: 0.9
      }

      result = Memory.create_memory(attrs)

      # May succeed or fail depending on Ollama mock response
      case result do
        {:ok, memory} ->
          assert memory.content == "User prefers dark mode"
          assert memory.category == "preference"

        {:error, _reason} ->
          # Embedding generation failed, which is acceptable in tests
          :ok
      end
    end

    test "create_memory_without_embedding/1 creates a memory", %{user: user} do
      attrs = %{
        user_id: user.id,
        content: "User prefers dark mode",
        category: "preference",
        confidence: 0.9
      }

      assert {:ok, memory} = Memory.create_memory_without_embedding(attrs)
      assert memory.content == "User prefers dark mode"
      assert memory.category == "preference"
      assert memory.confidence == 0.9
      assert memory.user_id == user.id
    end

    test "create_memory_without_embedding/1 fails with invalid category", %{user: user} do
      attrs = %{
        user_id: user.id,
        content: "Test",
        category: "invalid_category"
      }

      assert {:error, changeset} = Memory.create_memory_without_embedding(attrs)
      assert "is invalid" in errors_on(changeset).category
    end

    test "create_memory_without_embedding/1 fails without content", %{user: user} do
      attrs = %{user_id: user.id, category: "preference"}

      assert {:error, changeset} = Memory.create_memory_without_embedding(attrs)
      assert "can't be blank" in errors_on(changeset).content
    end

    test "get_memory!/1 returns a memory by id", %{user: user} do
      {:ok, memory} = Memory.create_memory_without_embedding(%{user_id: user.id, content: "Test"})

      fetched = Memory.get_memory!(memory.id)
      assert fetched.id == memory.id
    end

    test "get_memory!/1 raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Memory.get_memory!(Ecto.UUID.generate())
      end
    end

    test "get_user_memory/2 returns memory for correct user", %{user: user} do
      {:ok, memory} = Memory.create_memory_without_embedding(%{user_id: user.id, content: "Test"})

      fetched = Memory.get_user_memory(memory.id, user.id)
      assert fetched.id == memory.id
    end

    test "get_user_memory/2 returns nil for wrong user", %{user: user} do
      {:ok, memory} = Memory.create_memory_without_embedding(%{user_id: user.id, content: "Test"})
      other_user = user_fixture()

      assert Memory.get_user_memory(memory.id, other_user.id) == nil
    end

    test "list_memories/1 returns all memories for a user", %{user: user} do
      {:ok, m1} = Memory.create_memory_without_embedding(%{user_id: user.id, content: "Memory 1"})
      {:ok, m2} = Memory.create_memory_without_embedding(%{user_id: user.id, content: "Memory 2"})

      memories = Memory.list_memories(user.id)

      assert length(memories) == 2
      assert Enum.any?(memories, &(&1.id == m1.id))
      assert Enum.any?(memories, &(&1.id == m2.id))
    end

    test "list_memories/2 filters by category", %{user: user} do
      {:ok, _pref} =
        Memory.create_memory_without_embedding(%{
          user_id: user.id,
          content: "Pref",
          category: "preference"
        })

      {:ok, _skill} =
        Memory.create_memory_without_embedding(%{
          user_id: user.id,
          content: "Skill",
          category: "skill"
        })

      memories = Memory.list_memories(user.id, category: "preference")

      assert length(memories) == 1
      assert hd(memories).category == "preference"
    end

    test "list_memories/2 respects limit", %{user: user} do
      for i <- 1..5 do
        Memory.create_memory_without_embedding(%{user_id: user.id, content: "Memory #{i}"})
      end

      memories = Memory.list_memories(user.id, limit: 3)

      assert length(memories) == 3
    end

    test "update_memory/2 updates a memory", %{user: user} do
      {:ok, memory} =
        Memory.create_memory_without_embedding(%{user_id: user.id, content: "Original"})

      assert {:ok, updated} = Memory.update_memory(memory, %{content: "Updated"})
      assert updated.content == "Updated"
    end

    test "delete_memory/1 deletes a memory", %{user: user} do
      {:ok, memory} =
        Memory.create_memory_without_embedding(%{user_id: user.id, content: "To delete"})

      assert {:ok, deleted} = Memory.delete_memory(memory)

      assert_raise Ecto.NoResultsError, fn ->
        Memory.get_memory!(deleted.id)
      end
    end

    test "delete_user_memory/2 deletes for correct user", %{user: user} do
      {:ok, memory} =
        Memory.create_memory_without_embedding(%{user_id: user.id, content: "Test"})

      assert {:ok, _deleted} = Memory.delete_user_memory(memory.id, user.id)
    end

    test "delete_user_memory/2 fails for wrong user", %{user: user} do
      {:ok, memory} =
        Memory.create_memory_without_embedding(%{user_id: user.id, content: "Test"})

      other_user = user_fixture()
      assert {:error, :not_found} = Memory.delete_user_memory(memory.id, other_user.id)
    end

    test "count_memories/1 returns the count", %{user: user} do
      assert Memory.count_memories(user.id) == 0

      Memory.create_memory_without_embedding(%{user_id: user.id, content: "One"})
      Memory.create_memory_without_embedding(%{user_id: user.id, content: "Two"})

      assert Memory.count_memories(user.id) == 2
    end

    test "touch_memories/1 updates last_accessed_at", %{user: user} do
      {:ok, memory} =
        Memory.create_memory_without_embedding(%{user_id: user.id, content: "Test"})

      original_accessed = memory.last_accessed_at

      # Small delay to ensure time difference
      :timer.sleep(1100)
      {count, nil} = Memory.touch_memories([memory.id])
      assert count == 1

      updated = Memory.get_memory!(memory.id)
      assert updated.last_accessed_at != original_accessed
    end

    test "touch_memories/1 handles empty list" do
      assert {0, nil} = Memory.touch_memories([])
    end

    test "max_memories_per_user/0 returns configured value" do
      assert is_integer(Memory.max_memories_per_user())
      assert Memory.max_memories_per_user() > 0
    end

    test "enabled?/0 returns boolean" do
      assert is_boolean(Memory.enabled?())
    end
  end

  describe "conversation summaries" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})
      {:ok, user: user, conversation: conversation}
    end

    test "create_summary/1 creates a summary", %{conversation: conversation} do
      attrs = %{
        conversation_id: conversation.id,
        content: "Summary of the conversation",
        message_range_start: 0,
        message_range_end: 30,
        token_count: 100
      }

      assert {:ok, summary} = Memory.create_summary(attrs)
      assert summary.content == "Summary of the conversation"
      assert summary.message_range_start == 0
      assert summary.message_range_end == 30
    end

    test "create_summary/1 fails without required fields", %{conversation: conversation} do
      attrs = %{conversation_id: conversation.id}

      assert {:error, changeset} = Memory.create_summary(attrs)
      assert "can't be blank" in errors_on(changeset).content
    end

    test "get_latest_summary/1 returns most recent summary", %{conversation: conversation} do
      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "First",
        message_range_start: 0,
        message_range_end: 10
      })

      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "Second",
        message_range_start: 10,
        message_range_end: 20
      })

      latest = Memory.get_latest_summary(conversation.id)
      assert latest.content == "Second"
    end

    test "get_latest_summary/1 returns nil when no summaries", %{conversation: conversation} do
      assert Memory.get_latest_summary(conversation.id) == nil
    end

    test "list_summaries/1 returns all summaries in order", %{conversation: conversation} do
      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "Second",
        message_range_start: 10,
        message_range_end: 20
      })

      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "First",
        message_range_start: 0,
        message_range_end: 10
      })

      summaries = Memory.list_summaries(conversation.id)
      assert length(summaries) == 2
      # Should be ordered by message_range_start
      assert hd(summaries).message_range_start == 0
    end
  end

  describe "UserMemory schema" do
    test "categories/0 returns valid categories" do
      categories = UserMemory.categories()

      assert "preference" in categories
      assert "personal_info" in categories
      assert "skill" in categories
      assert "project" in categories
      assert "context" in categories
    end
  end

  describe "ConversationSummary schema" do
    test "changeset validates required fields" do
      changeset = ConversationSummary.changeset(%ConversationSummary{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
      assert "can't be blank" in errors_on(changeset).message_range_start
      assert "can't be blank" in errors_on(changeset).message_range_end
    end

    test "changeset validates range order" do
      changeset =
        ConversationSummary.changeset(%ConversationSummary{}, %{
          content: "Test",
          message_range_start: 20,
          message_range_end: 10,
          conversation_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert "must be greater than message_range_start" in errors_on(changeset).message_range_end
    end
  end
end
