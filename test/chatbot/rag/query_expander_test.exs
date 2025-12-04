defmodule Chatbot.RAG.QueryExpanderTest do
  use Chatbot.DataCase, async: false

  alias Chatbot.RAG.QueryExpander

  setup do
    # Disable query expansion to avoid API calls in tests
    original_config = Application.get_env(:chatbot, :rag, [])

    Application.put_env(
      :chatbot,
      :rag,
      Keyword.put(original_config, :query_expansion_enabled, false)
    )

    on_exit(fn ->
      Application.put_env(:chatbot, :rag, original_config)
    end)

    :ok
  end

  describe "expand/2" do
    test "returns {:ok, queries} tuple when expansion disabled" do
      result = QueryExpander.expand("test query", [])
      assert {:ok, queries} = result
      assert is_list(queries)
      assert "test query" in queries
    end

    test "includes only original query when expansion disabled" do
      {:ok, queries} = QueryExpander.expand("simple question", [])
      assert queries == ["simple question"]
    end

    test "handles various query formats" do
      {:ok, queries} = QueryExpander.expand("How do I authenticate with API keys?", [])
      assert queries == ["How do I authenticate with API keys?"]

      {:ok, queries2} = QueryExpander.expand("", [])
      assert queries2 == [""]
    end
  end
end
