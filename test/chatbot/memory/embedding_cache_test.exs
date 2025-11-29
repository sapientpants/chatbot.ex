defmodule Chatbot.Memory.EmbeddingCacheTest do
  use ExUnit.Case, async: false

  alias Chatbot.Memory.EmbeddingCache

  setup do
    # Clear cache before each test
    EmbeddingCache.clear()
    :ok
  end

  describe "get_or_compute/2" do
    test "computes and caches result on cache miss" do
      compute_fn = fn _text -> {:ok, [1.0, 2.0, 3.0]} end

      # First call - should compute
      result1 = EmbeddingCache.get_or_compute("test text unique1", compute_fn)
      assert {:ok, [1.0, 2.0, 3.0]} = result1

      # Track if compute_fn is called again
      call_count = :counters.new(1, [:atomics])

      compute_fn_tracked = fn _text ->
        :counters.add(call_count, 1, 1)
        {:ok, [4.0, 5.0, 6.0]}
      end

      # Second call with same text - should use cache
      result2 = EmbeddingCache.get_or_compute("test text unique1", compute_fn_tracked)
      assert {:ok, [1.0, 2.0, 3.0]} = result2

      # Compute function should not have been called
      assert :counters.get(call_count, 1) == 0
    end

    test "returns error from compute function" do
      compute_fn = fn _text -> {:error, :embedding_failed} end

      result = EmbeddingCache.get_or_compute("error test unique", compute_fn)

      assert {:error, :embedding_failed} = result
    end

    test "caches different texts separately" do
      compute_fn = fn text -> {:ok, [String.length(text) * 1.0]} end

      result1 = EmbeddingCache.get_or_compute("short", compute_fn)
      result2 = EmbeddingCache.get_or_compute("much longer text", compute_fn)

      assert {:ok, [5.0]} = result1
      assert {:ok, [16.0]} = result2
    end

    test "handles concurrent requests for same key" do
      # Slow compute function
      compute_fn = fn _text ->
        Process.sleep(50)
        {:ok, [1.0]}
      end

      # Start multiple concurrent requests
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            EmbeddingCache.get_or_compute("concurrent test unique", compute_fn)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed with same result
      assert Enum.all?(results, &match?({:ok, [1.0]}, &1))
    end
  end

  describe "put/2" do
    test "stores value in cache" do
      EmbeddingCache.put("key1 unique", [1.0])
      EmbeddingCache.put("key2 unique", [2.0])

      # Give the async cast time to complete
      Process.sleep(10)

      # Use get_or_compute to check - should return cached value
      compute_fn = fn _text -> {:ok, [999.0]} end

      assert {:ok, [1.0]} = EmbeddingCache.get_or_compute("key1 unique", compute_fn)
      assert {:ok, [2.0]} = EmbeddingCache.get_or_compute("key2 unique", compute_fn)
    end
  end

  describe "clear/0" do
    test "removes all entries" do
      EmbeddingCache.put("clear_key1", [1.0])
      EmbeddingCache.put("clear_key2", [2.0])
      Process.sleep(10)

      EmbeddingCache.clear()
      Process.sleep(10)

      # After clear, should compute again
      compute_fn = fn _text -> {:ok, [999.0]} end

      result = EmbeddingCache.get_or_compute("clear_key1", compute_fn)
      assert {:ok, [999.0]} = result
    end
  end

  describe "size/0" do
    test "returns cache size" do
      # Clear first to ensure clean state
      EmbeddingCache.clear()
      Process.sleep(10)

      EmbeddingCache.put("size_key1", [1.0])
      EmbeddingCache.put("size_key2", [2.0])
      Process.sleep(10)

      assert EmbeddingCache.size() == 2
    end
  end
end
