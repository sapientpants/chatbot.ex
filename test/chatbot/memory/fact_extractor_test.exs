defmodule Chatbot.Memory.FactExtractorTest do
  use Chatbot.DataCase, async: false

  import Mox

  alias Chatbot.Memory
  alias Chatbot.Memory.FactExtractor

  setup :set_mox_global
  setup :verify_on_exit!

  describe "parse_response/1" do
    test "parses valid JSON array" do
      response =
        ~s|[{"content": "User likes coffee", "category": "preference", "confidence": 0.9}]|

      assert {:ok, [fact]} = FactExtractor.parse_response(response)
      assert fact.content == "User likes coffee"
      assert fact.category == "preference"
      assert fact.confidence == 0.9
    end

    test "parses empty array" do
      response = "[]"

      assert {:ok, []} = FactExtractor.parse_response(response)
    end

    test "parses multiple facts" do
      response = ~s|[
        {"content": "Fact 1", "category": "preference", "confidence": 0.8},
        {"content": "Fact 2", "category": "skill", "confidence": 0.9}
      ]|

      assert {:ok, facts} = FactExtractor.parse_response(response)
      assert length(facts) == 2
    end

    test "handles markdown code blocks" do
      response = ~s|```json
[{"content": "User is a developer", "category": "skill", "confidence": 0.95}]
```|

      assert {:ok, [fact]} = FactExtractor.parse_response(response)
      assert fact.content == "User is a developer"
    end

    test "handles code block without json label" do
      response = ~s|```
[{"content": "Test fact", "category": "context", "confidence": 0.7}]
```|

      assert {:ok, [fact]} = FactExtractor.parse_response(response)
      assert fact.content == "Test fact"
    end

    test "extracts JSON from mixed text" do
      response = ~s|Here are the facts I found:
[{"content": "Extracted fact", "category": "personal_info", "confidence": 0.85}]
That's all I found.|

      assert {:ok, [fact]} = FactExtractor.parse_response(response)
      assert fact.content == "Extracted fact"
    end

    test "returns error for invalid JSON" do
      response = "not valid json at all"

      assert {:error, :invalid_json} = FactExtractor.parse_response(response)
    end

    test "returns error for non-array JSON" do
      response = ~s|{"content": "single object"}|

      assert {:error, :invalid_json} = FactExtractor.parse_response(response)
    end

    test "filters out invalid facts" do
      response = ~s|[
        {"content": "Valid fact", "category": "preference", "confidence": 0.9},
        {"content": "", "category": "preference", "confidence": 0.9},
        {"content": "Missing category"},
        {"content": "Invalid category", "category": "not_a_category", "confidence": 0.9}
      ]|

      assert {:ok, facts} = FactExtractor.parse_response(response)
      assert length(facts) == 1
      assert hd(facts).content == "Valid fact"
    end

    test "normalizes confidence values" do
      response = ~s|[
        {"content": "Fact 1", "category": "preference", "confidence": 1.5},
        {"content": "Fact 2", "category": "preference", "confidence": -0.5},
        {"content": "Fact 3", "category": "preference", "confidence": null},
        {"content": "Fact 4", "category": "preference"}
      ]|

      assert {:ok, facts} = FactExtractor.parse_response(response)

      confidences = Enum.map(facts, & &1.confidence)

      # All should be clamped to 0.0-1.0 or defaulted to 0.5
      assert Enum.all?(confidences, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "handles whitespace in response" do
      response = ~s|

        [{"content": "Fact with whitespace", "category": "preference", "confidence": 0.8}]

      |

      assert {:ok, [fact]} = FactExtractor.parse_response(response)
      assert fact.content == "Fact with whitespace"
    end
  end

  describe "extract_and_store/5" do
    setup do
      user = Chatbot.Fixtures.user_fixture()
      {:ok, conversation} = Chatbot.Chat.create_conversation(%{user_id: user.id, title: "Test"})

      {:ok, message} =
        Chatbot.Chat.create_message(%{
          conversation_id: conversation.id,
          role: "assistant",
          content: "Test response"
        })

      {:ok, user: user, message: message}
    end

    test "returns :ok when extraction is disabled", %{user: user, message: message} do
      # Temporarily disable extraction
      original = Application.get_env(:chatbot, :memory, [])

      Application.put_env(
        :chatbot,
        :memory,
        Keyword.put(original, :fact_extraction_enabled, false)
      )

      result =
        FactExtractor.extract_and_store(
          user.id,
          "User message",
          "Assistant response",
          message.id,
          "test-model"
        )

      assert result == :ok

      # Restore config
      Application.put_env(:chatbot, :memory, original)
    end

    test "extracts and stores facts when LLM returns valid response", %{
      user: user,
      message: message
    } do
      # Configure to use mock
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      # Mock LLM response with valid facts
      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   ~s|[{"content": "User prefers dark mode", "category": "preference", "confidence": 0.9}]|
               }
             }
           ]
         }}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "I really prefer dark mode for coding",
          "I've noted your preference for dark mode!",
          message.id,
          "test-model"
        )

      assert result == :ok

      # Verify the memory was stored
      memories = Memory.list_memories(user.id)
      assert length(memories) == 1
      assert hd(memories).content == "User prefers dark mode"

      # Restore config
      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "returns :ok when LLM returns empty facts array", %{user: user, message: message} do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{"content" => "[]"}
             }
           ]
         }}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "What's 2+2?",
          "It's 4!",
          message.id,
          "test-model"
        )

      assert result == :ok

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "handles LLM error gracefully", %{user: user, message: message} do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:error, "Connection refused"}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "Test message",
          "Test response",
          message.id,
          "test-model"
        )

      assert {:error, "Connection refused"} = result

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "handles unexpected response format", %{user: user, message: message} do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok, %{"unexpected" => "format"}}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "Test message",
          "Test response",
          message.id,
          "test-model"
        )

      assert {:error, :unexpected_response} = result

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "handles invalid JSON from LLM gracefully", %{user: user, message: message} do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{"content" => "I found some facts but forgot to format them as JSON"}
             }
           ]
         }}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "Test message",
          "Test response",
          message.id,
          "test-model"
        )

      # Should return :ok even when parsing fails (logged as warning)
      assert result == :ok

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "filters low confidence facts", %{user: user, message: message} do
      original = Application.get_env(:chatbot, :lm_studio_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{
                 "content" => ~s|[
                {"content": "High confidence fact", "category": "preference", "confidence": 0.9},
                {"content": "Low confidence fact", "category": "preference", "confidence": 0.1}
              ]|
               }
             }
           ]
         }}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "Some message",
          "Some response",
          message.id,
          "test-model"
        )

      assert result == :ok

      # Only high confidence fact should be stored
      memories = Memory.list_memories(user.id)
      assert length(memories) == 1
      assert hd(memories).content == "High confidence fact"

      if original,
        do: Application.put_env(:chatbot, :lm_studio_client, original),
        else: Application.delete_env(:chatbot, :lm_studio_client)
    end

    test "skips duplicate facts based on similarity", %{user: user, message: message} do
      original_lm = Application.get_env(:chatbot, :lm_studio_client)
      original_ollama = Application.get_env(:chatbot, :ollama_client)
      Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)
      Application.put_env(:chatbot, :ollama_client, Chatbot.OllamaMock)

      # First, create an existing memory
      embedding = List.duplicate(0.1, 1024)

      {:ok, _memory} =
        Memory.create_memory(%{
          user_id: user.id,
          content: "User prefers dark mode",
          category: "preference",
          confidence: 0.9,
          embedding: Pgvector.new(embedding),
          source_message_id: message.id
        })

      # Mock embedding for similarity search
      stub(Chatbot.OllamaMock, :embed, fn _text -> {:ok, embedding} end)
      stub(Chatbot.OllamaMock, :embedding_dimension, fn -> 1024 end)

      # Try to extract a very similar fact
      expect(Chatbot.LMStudioMock, :chat_completion, fn _messages, _model ->
        {:ok,
         %{
           "choices" => [
             %{
               "message" => %{
                 "content" =>
                   ~s|[{"content": "User prefers dark mode", "category": "preference", "confidence": 0.9}]|
               }
             }
           ]
         }}
      end)

      result =
        FactExtractor.extract_and_store(
          user.id,
          "I like dark mode",
          "Got it!",
          message.id,
          "test-model"
        )

      assert result == :ok

      # Should still only have one memory (duplicate was skipped)
      memories = Memory.list_memories(user.id)
      assert length(memories) == 1

      if original_lm,
        do: Application.put_env(:chatbot, :lm_studio_client, original_lm),
        else: Application.delete_env(:chatbot, :lm_studio_client)

      if original_ollama,
        do: Application.put_env(:chatbot, :ollama_client, original_ollama),
        else: Application.delete_env(:chatbot, :ollama_client)
    end
  end
end
