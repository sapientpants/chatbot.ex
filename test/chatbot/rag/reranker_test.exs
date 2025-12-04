defmodule Chatbot.RAG.RerankerTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.RAG.Reranker

  describe "rerank/3" do
    test "returns {:ok, chunks} tuple with scores" do
      chunks = [
        %{content: "chunk 1", score: 0.9},
        %{content: "chunk 2", score: 0.8}
      ]

      result = Reranker.rerank("test query", chunks, [])
      assert {:ok, reranked} = result
      assert is_list(reranked)
    end

    test "handles empty chunks list" do
      {:ok, result} = Reranker.rerank("test query", [], [])
      assert result == []
    end
  end
end
