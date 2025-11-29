defmodule Chatbot.Memory.FactExtractorTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Memory.FactExtractor

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
  end
end
