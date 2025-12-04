defmodule Chatbot.RAG.QueryExpanderTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.RAG.QueryExpander

  describe "expand/2" do
    test "returns {:ok, queries} tuple" do
      result = QueryExpander.expand("test query", [])
      assert {:ok, queries} = result
      assert is_list(queries)
      assert "test query" in queries
    end

    test "includes original query in expanded queries" do
      {:ok, queries} = QueryExpander.expand("simple question", [])
      assert is_list(queries)
      assert "simple question" in queries
    end
  end
end
