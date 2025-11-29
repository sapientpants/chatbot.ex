defmodule Chatbot.Memory.SummarizerTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Memory
  alias Chatbot.Memory.Summarizer

  import Chatbot.Fixtures

  describe "get_combined_summary/1" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})
      {:ok, conversation: conversation}
    end

    test "returns nil when no summaries exist", %{conversation: conversation} do
      result = Summarizer.get_combined_summary(conversation.id)

      assert result == nil
    end

    test "returns formatted summary when one exists", %{conversation: conversation} do
      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "This is a summary",
        message_range_start: 0,
        message_range_end: 30
      })

      result = Summarizer.get_combined_summary(conversation.id)

      assert result =~ "Previous conversation context:"
      assert result =~ "This is a summary"
    end

    test "combines multiple summaries", %{conversation: conversation} do
      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "First summary",
        message_range_start: 0,
        message_range_end: 30
      })

      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "Second summary",
        message_range_start: 30,
        message_range_end: 60
      })

      result = Summarizer.get_combined_summary(conversation.id)

      assert result =~ "First summary"
      assert result =~ "Second summary"
    end
  end

  describe "maybe_summarize/2" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})
      {:ok, user: user, conversation: conversation}
    end

    test "returns {:ok, nil} when below threshold", %{conversation: conversation} do
      # Add just a few messages (below threshold)
      for i <- 1..5 do
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: if(rem(i, 2) == 0, do: "assistant", else: "user"),
          content: "Message #{i}"
        })
      end

      result = Summarizer.maybe_summarize(conversation.id, "test-model")

      assert {:ok, nil} = result
    end

    test "returns {:ok, nil} when already summarized", %{conversation: conversation} do
      # Add messages at threshold
      for i <- 1..35 do
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: if(rem(i, 2) == 0, do: "assistant", else: "user"),
          content: "Message #{i}"
        })
      end

      # Create a summary covering most messages
      Memory.create_summary(%{
        conversation_id: conversation.id,
        content: "Existing summary",
        message_range_start: 0,
        message_range_end: 30
      })

      # Won't generate new summary since not enough unsummarized messages
      result = Summarizer.maybe_summarize(conversation.id, "test-model")

      assert {:ok, nil} = result
    end
  end

  describe "generate_summary/4" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})

      messages =
        for i <- 1..40 do
          {:ok, msg} =
            Chatbot.Chat.create_message(%{
              conversation_id: conversation.id,
              role: if(rem(i, 2) == 0, do: "assistant", else: "user"),
              content: "Message #{i}"
            })

          msg
        end

      {:ok, conversation: conversation, messages: messages}
    end

    test "returns {:ok, nil} when range is invalid", %{
      conversation: conversation,
      messages: messages
    } do
      # start_index >= end_index should return nil
      result = Summarizer.generate_summary(conversation.id, messages, 35, "test-model")

      assert {:ok, nil} = result
    end
  end
end
