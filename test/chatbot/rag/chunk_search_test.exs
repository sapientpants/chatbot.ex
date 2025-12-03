defmodule Chatbot.RAG.ChunkSearchTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Chat.AttachmentChunk
  alias Chatbot.RAG.ChunkSearch

  import Chatbot.Fixtures

  describe "rrf_fusion/4" do
    test "combines results from both search methods" do
      semantic = [
        %{id: "a", rank: 1},
        %{id: "b", rank: 2},
        %{id: "c", rank: 3}
      ]

      keyword = [
        %{id: "b", rank: 1},
        %{id: "d", rank: 2},
        %{id: "a", rank: 3}
      ]

      result = ChunkSearch.rrf_fusion(semantic, keyword, 0.6, 0.4)

      # b appears in both with good ranks, should be ranked highest
      assert hd(result) == "b"
      # All IDs should be present
      assert length(result) == 4
    end

    test "handles empty semantic results" do
      keyword = [%{id: "a", rank: 1}]

      result = ChunkSearch.rrf_fusion([], keyword, 0.6, 0.4)

      assert result == ["a"]
    end

    test "handles empty keyword results" do
      semantic = [%{id: "a", rank: 1}]

      result = ChunkSearch.rrf_fusion(semantic, [], 0.6, 0.4)

      assert result == ["a"]
    end

    test "handles both empty" do
      result = ChunkSearch.rrf_fusion([], [], 0.6, 0.4)

      assert result == []
    end

    test "respects weight parameters" do
      semantic = [%{id: "a", rank: 1}]
      keyword = [%{id: "b", rank: 1}]

      # With high semantic weight, "a" should win
      result_high_semantic = ChunkSearch.rrf_fusion(semantic, keyword, 0.9, 0.1)
      assert hd(result_high_semantic) == "a"

      # With high keyword weight, "b" should win
      result_high_keyword = ChunkSearch.rrf_fusion(semantic, keyword, 0.1, 0.9)
      assert hd(result_high_keyword) == "b"
    end
  end

  describe "semantic_search/3" do
    test "returns empty list when no chunks exist" do
      conversation = conversation_fixture()
      embedding = Pgvector.new(List.duplicate(0.1, 1024))

      result = ChunkSearch.semantic_search(conversation.id, embedding, limit: 5)

      assert result == []
    end

    test "finds chunks by vector similarity" do
      attachment = attachment_fixture_without_chunks()
      embedding = List.duplicate(0.1, 1024)
      chunk = attachment_chunk_fixture(attachment: attachment, embedding: embedding)

      query_embedding = Pgvector.new(embedding)

      results =
        ChunkSearch.semantic_search(
          attachment.conversation_id,
          query_embedding,
          limit: 5
        )

      assert length(results) == 1
      assert hd(results).id == chunk.id
    end

    test "respects limit parameter" do
      attachment = attachment_fixture_without_chunks()
      embedding = List.duplicate(0.1, 1024)

      # Create multiple chunks
      for i <- 0..4 do
        attachment_chunk_fixture(
          attachment: attachment,
          embedding: embedding,
          content: "Chunk #{i}",
          chunk_index: i
        )
      end

      query_embedding = Pgvector.new(embedding)

      results =
        ChunkSearch.semantic_search(
          attachment.conversation_id,
          query_embedding,
          limit: 3
        )

      assert length(results) == 3
    end

    test "filters by conversation_id" do
      # Create two conversations with chunks
      attachment1 = attachment_fixture_without_chunks()
      attachment2 = attachment_fixture_without_chunks()
      embedding = List.duplicate(0.1, 1024)

      chunk1 = attachment_chunk_fixture(attachment: attachment1, embedding: embedding)
      _chunk2 = attachment_chunk_fixture(attachment: attachment2, embedding: embedding)

      query_embedding = Pgvector.new(embedding)

      results =
        ChunkSearch.semantic_search(
          attachment1.conversation_id,
          query_embedding,
          limit: 10
        )

      # Should only find chunk from conversation1
      assert length(results) == 1
      assert hd(results).id == chunk1.id
    end
  end

  describe "keyword_search/3" do
    test "returns empty list when no chunks exist" do
      conversation = conversation_fixture()

      result = ChunkSearch.keyword_search(conversation.id, "test query", limit: 5)

      assert result == []
    end

    test "returns empty list for empty query" do
      conversation = conversation_fixture()

      result = ChunkSearch.keyword_search(conversation.id, "", limit: 5)

      assert result == []
    end

    test "finds chunks by keyword match" do
      attachment = attachment_fixture_without_chunks()

      chunk =
        attachment_chunk_fixture(
          attachment: attachment,
          content: "This document describes Elixir programming language"
        )

      results =
        ChunkSearch.keyword_search(
          attachment.conversation_id,
          "Elixir programming",
          limit: 5
        )

      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == chunk.id))
    end

    test "handles special characters gracefully" do
      conversation = conversation_fixture()

      # Should not crash
      result = ChunkSearch.keyword_search(conversation.id, "test @#$% query!", limit: 5)

      assert is_list(result)
    end
  end

  describe "deduplicate/1" do
    test "removes chunks with same content_hash" do
      attachment = attachment_fixture_without_chunks()
      embedding = List.duplicate(0.1, 1024)

      # Create two chunks with same content (same hash)
      chunk1 =
        attachment_chunk_fixture(
          attachment: attachment,
          content: "Same content",
          chunk_index: 0,
          embedding: embedding
        )

      _chunk2 =
        attachment_chunk_fixture(
          attachment: attachment,
          content: "Same content",
          chunk_index: 1,
          embedding: embedding
        )

      # Load chunks from DB
      chunks = Repo.all(AttachmentChunk)

      deduplicated = ChunkSearch.deduplicate(chunks)

      # Should have only one chunk after deduplication
      assert length(deduplicated) == 1
      assert hd(deduplicated).id == chunk1.id
    end

    test "keeps chunks with different content" do
      attachment = attachment_fixture_without_chunks()
      embedding = List.duplicate(0.1, 1024)

      attachment_chunk_fixture(
        attachment: attachment,
        content: "Content A",
        chunk_index: 0,
        embedding: embedding
      )

      attachment_chunk_fixture(
        attachment: attachment,
        content: "Content B",
        chunk_index: 1,
        embedding: embedding
      )

      chunks = Repo.all(AttachmentChunk)

      deduplicated = ChunkSearch.deduplicate(chunks)

      assert length(deduplicated) == 2
    end
  end

  describe "search/3" do
    test "returns empty list when no chunks exist" do
      conversation = conversation_fixture()

      # Search may fail due to embedding service not being available in test
      # but should handle gracefully
      result = ChunkSearch.search(conversation.id, "test query")

      case result do
        {:ok, chunks} -> assert chunks == []
        {:error, _reason} -> :ok
      end
    end
  end
end
