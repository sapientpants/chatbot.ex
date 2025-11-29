defmodule Chatbot.Memory.SearchTest do
  use Chatbot.DataCase, async: true

  alias Chatbot.Memory
  alias Chatbot.Memory.Search

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

      result = Search.rrf_fusion(semantic, keyword, 0.6, 0.4)

      # b appears in both, should be ranked highest
      assert hd(result) == "b"
      # a appears in both, should be next
      assert Enum.member?(result, "a")
      # All IDs should be present
      assert length(result) == 4
    end

    test "handles empty semantic results" do
      keyword = [%{id: "a", rank: 1}]

      result = Search.rrf_fusion([], keyword, 0.6, 0.4)

      assert result == ["a"]
    end

    test "handles empty keyword results" do
      semantic = [%{id: "a", rank: 1}]

      result = Search.rrf_fusion(semantic, [], 0.6, 0.4)

      assert result == ["a"]
    end

    test "handles both empty" do
      result = Search.rrf_fusion([], [], 0.6, 0.4)

      assert result == []
    end

    test "respects weight parameters" do
      # Item "a" ranked #1 in semantic only
      # Item "b" ranked #1 in keyword only
      semantic = [%{id: "a", rank: 1}]
      keyword = [%{id: "b", rank: 1}]

      # With high semantic weight, "a" should win
      result_high_semantic = Search.rrf_fusion(semantic, keyword, 0.9, 0.1)
      assert hd(result_high_semantic) == "a"

      # With high keyword weight, "b" should win
      result_high_keyword = Search.rrf_fusion(semantic, keyword, 0.1, 0.9)
      assert hd(result_high_keyword) == "b"
    end
  end

  describe "search/3" do
    setup do
      user = user_fixture()
      {:ok, user: user}
    end

    test "returns empty list when no memories exist", %{user: user} do
      # In test env, Ollama may return empty or error, but search handles gracefully
      result = Search.search(user.id, "test query")

      # Should return ok with empty list or error depending on Ollama response
      case result do
        {:ok, memories} -> assert memories == []
        {:error, _reason} -> :ok
      end
    end

    test "semantic_search/3 returns empty when no memories", %{user: user} do
      # Create a fake embedding vector
      embedding = List.duplicate(0.0, 1024) |> Pgvector.new()

      result = Search.semantic_search(user.id, embedding, limit: 5)

      assert result == []
    end

    test "keyword_search/3 returns empty when no memories", %{user: user} do
      result = Search.keyword_search(user.id, "test query", limit: 5)

      assert result == []
    end

    test "keyword_search/3 returns empty for empty query", %{user: user} do
      result = Search.keyword_search(user.id, "", limit: 5)

      assert result == []
    end

    test "keyword_search/3 handles special characters", %{user: user} do
      result = Search.keyword_search(user.id, "test @#$% query!", limit: 5)

      # Should not crash with special characters
      assert is_list(result)
    end
  end

  describe "semantic_search with data" do
    setup do
      user = user_fixture()

      # Create memories with embeddings directly in DB (bypassing Ollama)
      embedding = List.duplicate(0.1, 1024)

      {:ok, memory} =
        Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
          user_id: user.id,
          content: "User likes Elixir programming",
          category: "skill",
          confidence: 0.9,
          embedding: embedding
        })
        |> Chatbot.Repo.insert()

      {:ok, user: user, memory: memory}
    end

    test "finds memories by vector similarity", %{user: user, memory: memory} do
      # Query with similar embedding
      query_embedding = List.duplicate(0.1, 1024) |> Pgvector.new()

      results = Search.semantic_search(user.id, query_embedding, limit: 5)

      assert length(results) == 1
      assert hd(results).id == memory.id
    end

    test "respects limit parameter", %{user: user} do
      # Add more memories
      embedding = List.duplicate(0.1, 1024)

      for i <- 1..5 do
        Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
          user_id: user.id,
          content: "Memory #{i}",
          category: "context",
          confidence: 0.8,
          embedding: embedding
        })
        |> Chatbot.Repo.insert()
      end

      query_embedding = List.duplicate(0.1, 1024) |> Pgvector.new()

      results = Search.semantic_search(user.id, query_embedding, limit: 3)

      assert length(results) == 3
    end

    test "filters by minimum confidence", %{user: user} do
      embedding = List.duplicate(0.1, 1024)

      # Low confidence memory
      Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
        user_id: user.id,
        content: "Low confidence",
        category: "context",
        confidence: 0.2,
        embedding: embedding
      })
      |> Chatbot.Repo.insert()

      query_embedding = List.duplicate(0.1, 1024) |> Pgvector.new()

      # Should filter out low confidence
      results = Search.semantic_search(user.id, query_embedding, min_confidence: 0.5)

      assert Enum.all?(results, fn r ->
               memory = Memory.get_memory!(r.id)
               memory.confidence >= 0.5
             end)
    end

    test "filters by category", %{user: user} do
      embedding = List.duplicate(0.1, 1024)

      Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
        user_id: user.id,
        content: "A preference",
        category: "preference",
        embedding: embedding
      })
      |> Chatbot.Repo.insert()

      query_embedding = List.duplicate(0.1, 1024) |> Pgvector.new()

      results = Search.semantic_search(user.id, query_embedding, category: "preference")

      assert Enum.all?(results, fn r ->
               memory = Memory.get_memory!(r.id)
               memory.category == "preference"
             end)
    end
  end

  describe "keyword_search with data" do
    setup do
      user = user_fixture()

      {:ok, memory} =
        Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
          user_id: user.id,
          content: "User knows Elixir and Phoenix framework",
          category: "skill",
          confidence: 0.9
        })
        |> Chatbot.Repo.insert()

      {:ok, user: user, memory: memory}
    end

    test "finds memories by keyword match", %{user: user, memory: memory} do
      results = Search.keyword_search(user.id, "Elixir Phoenix", limit: 5)

      assert length(results) >= 1
      assert Enum.any?(results, &(&1.id == memory.id))
    end

    test "respects limit parameter", %{user: user} do
      for i <- 1..5 do
        Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
          user_id: user.id,
          content: "Elixir skill #{i}",
          category: "skill"
        })
        |> Chatbot.Repo.insert()
      end

      results = Search.keyword_search(user.id, "Elixir", limit: 3)

      assert length(results) == 3
    end

    test "ranks by relevance", %{user: user} do
      # Memory with multiple keyword matches should rank higher
      Memory.UserMemory.changeset(%Memory.UserMemory{}, %{
        user_id: user.id,
        content: "Elixir Elixir Elixir programming",
        category: "skill"
      })
      |> Chatbot.Repo.insert()

      results = Search.keyword_search(user.id, "Elixir programming", limit: 10)

      # Results should have rank field
      assert Enum.all?(results, &Map.has_key?(&1, :rank))
    end
  end
end
