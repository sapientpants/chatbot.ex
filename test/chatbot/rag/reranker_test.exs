defmodule Chatbot.RAG.RerankerTest do
  use Chatbot.DataCase, async: false

  alias Chatbot.Chat.AttachmentChunk
  alias Chatbot.RAG.Reranker

  setup do
    # Disable reranking to avoid API calls in tests
    original_config = Application.get_env(:chatbot, :rag, [])
    Application.put_env(:chatbot, :rag, Keyword.put(original_config, :reranking_enabled, false))

    on_exit(fn ->
      Application.put_env(:chatbot, :rag, original_config)
    end)

    :ok
  end

  describe "rerank/3" do
    test "returns {:ok, chunks} tuple with scores when reranking disabled" do
      chunks = [
        %AttachmentChunk{
          id: Ecto.UUID.generate(),
          attachment_id: Ecto.UUID.generate(),
          content: "chunk 1",
          chunk_index: 0,
          embedding: nil,
          metadata: %{}
        },
        %AttachmentChunk{
          id: Ecto.UUID.generate(),
          attachment_id: Ecto.UUID.generate(),
          content: "chunk 2",
          chunk_index: 1,
          embedding: nil,
          metadata: %{}
        }
      ]

      result = Reranker.rerank("test query", chunks, [])
      assert {:ok, reranked} = result
      assert is_list(reranked)
      assert length(reranked) == 2

      # Each element should be a {chunk, score} tuple
      Enum.each(reranked, fn {chunk, score} ->
        assert %AttachmentChunk{} = chunk
        assert is_float(score)
      end)
    end

    test "handles empty chunks list" do
      {:ok, result} = Reranker.rerank("test query", [], [])
      assert result == []
    end

    test "returns chunks in order with decreasing placeholder scores" do
      chunks = [
        %AttachmentChunk{
          id: Ecto.UUID.generate(),
          attachment_id: Ecto.UUID.generate(),
          content: "first",
          chunk_index: 0,
          embedding: nil,
          metadata: %{}
        },
        %AttachmentChunk{
          id: Ecto.UUID.generate(),
          attachment_id: Ecto.UUID.generate(),
          content: "second",
          chunk_index: 1,
          embedding: nil,
          metadata: %{}
        }
      ]

      {:ok, reranked} = Reranker.rerank("query", chunks, [])

      [{first_chunk, first_score}, {second_chunk, second_score}] = reranked
      assert first_chunk.content == "first"
      assert second_chunk.content == "second"
      assert first_score > second_score
    end
  end

  describe "rerank_chunks/3" do
    test "returns only chunks without scores" do
      chunks = [
        %AttachmentChunk{
          id: Ecto.UUID.generate(),
          attachment_id: Ecto.UUID.generate(),
          content: "test content",
          chunk_index: 0,
          embedding: nil,
          metadata: %{}
        }
      ]

      {:ok, result} = Reranker.rerank_chunks("query", chunks, [])
      assert is_list(result)
      assert length(result) == 1
      assert [%AttachmentChunk{content: "test content"}] = result
    end
  end
end
