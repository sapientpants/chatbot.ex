defmodule Chatbot.Memory.SummarizerTest do
  use Chatbot.DataCase, async: false

  import Mox

  alias Chatbot.Memory
  alias Chatbot.Memory.Summarizer

  import Chatbot.Fixtures

  setup :set_mox_global
  setup :verify_on_exit!

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

    test "creates summary when LLM returns valid response", %{
      conversation: conversation,
      messages: messages
    } do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{
                 "content" => "This is a summary of the conversation discussing various topics."
               }
             }
           ]
         }}
      end)

      result = Summarizer.generate_summary(conversation.id, messages, 0, "test-model")

      assert {:ok, summary} = result
      assert summary.content == "This is a summary of the conversation discussing various topics."
      assert summary.conversation_id == conversation.id
      assert summary.message_range_start == 0

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "handles LLM error gracefully", %{
      conversation: conversation,
      messages: messages
    } do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:error, "Connection refused"}
      end)

      result = Summarizer.generate_summary(conversation.id, messages, 0, "test-model")

      assert {:error, "Connection refused"} = result

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "handles unexpected response format", %{
      conversation: conversation,
      messages: messages
    } do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok, %{"unexpected" => "format"}}
      end)

      result = Summarizer.generate_summary(conversation.id, messages, 0, "test-model")

      assert {:error, :unexpected_response} = result

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end
  end

  describe "maybe_summarize/2 with LLM" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})
      {:ok, user: user, conversation: conversation}
    end

    test "generates summary when threshold is exceeded", %{conversation: conversation} do
      original = Application.get_env(:chatbot, :lm_studio_client)
      original_memory = Application.get_env(:chatbot, :memory, [])
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)
      # Set a low threshold for testing
      Application.put_env(
        :chatbot,
        :memory,
        Keyword.put(original_memory, :summarization_threshold, 10)
      )

      # Add messages at threshold
      for i <- 1..35 do
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: if(rem(i, 2) == 0, do: "assistant", else: "user"),
          content: "Message #{i} with some content"
        })
      end

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{
                 "content" => "Summary: Users discussed various numbered messages."
               }
             }
           ]
         }}
      end)

      result = Summarizer.maybe_summarize(conversation.id, "test-model")

      assert {:ok, summary} = result
      assert summary.content == "Summary: Users discussed various numbered messages."

      Application.put_env(:chatbot, :memory, original_memory)

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end
  end
end
