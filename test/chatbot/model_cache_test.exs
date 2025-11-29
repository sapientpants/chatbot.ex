defmodule Chatbot.ModelCacheTest do
  use ExUnit.Case, async: false

  import Mox

  alias Chatbot.ModelCache

  # Use global mode for Mox since ModelCache is a GenServer
  # that runs in a separate process
  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Configure test to use mocks for both providers
    Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)
    Application.put_env(:chatbot, :ollama_client, Chatbot.OllamaMock)
    # Use a very short TTL for testing
    Application.put_env(:chatbot, :model_cache, ttl_ms: 50)

    # Clear the cache before each test
    if Process.whereis(ModelCache) do
      ModelCache.clear()
      # Wait a bit for the clear to complete
      Process.sleep(10)
    end

    on_exit(fn ->
      Application.delete_env(:chatbot, :lm_studio_client)
      Application.delete_env(:chatbot, :ollama_client)
      Application.put_env(:chatbot, :model_cache, ttl_ms: 60_000)
    end)

    :ok
  end

  # Helper to set up Ollama mock expectations (LM Studio disabled by default)
  defp expect_ollama_models(models) do
    expect(Chatbot.OllamaMock, :list_models, fn -> {:ok, models} end)
  end

  describe "get_models/0" do
    test "fetches models from Ollama on cache miss" do
      ollama_models = [
        %{"id" => "ollama/test-model", "name" => "test-model", "provider" => "ollama"}
      ]

      expect_ollama_models(ollama_models)

      assert {:ok, ^ollama_models} = ModelCache.get_models()
    end

    test "returns cached models on cache hit" do
      ollama_models = [
        %{"id" => "ollama/cached-model", "name" => "cached-model", "provider" => "ollama"}
      ]

      # First call fetches from API
      expect_ollama_models(ollama_models)

      assert {:ok, ^ollama_models} = ModelCache.get_models()

      # Second call should use cache (no additional API call expected)
      assert {:ok, ^ollama_models} = ModelCache.get_models()
    end

    test "fetches new models after TTL expires" do
      models_v1 = [
        %{"id" => "ollama/model-v1", "name" => "model-v1", "provider" => "ollama"}
      ]

      models_v2 = [
        %{"id" => "ollama/model-v2", "name" => "model-v2", "provider" => "ollama"}
      ]

      # First call
      expect_ollama_models(models_v1)

      assert {:ok, ^models_v1} = ModelCache.get_models()

      # Wait for TTL to expire (50ms + buffer)
      Process.sleep(60)

      # Second call should fetch fresh data
      expect_ollama_models(models_v2)

      assert {:ok, ^models_v2} = ModelCache.get_models()
    end

    test "returns empty list when Ollama fails and LM Studio is disabled" do
      # When Ollama fails but LM Studio is disabled, we get an empty model list
      # rather than an error (graceful degradation)
      expect(Chatbot.OllamaMock, :list_models, fn -> {:error, "Connection refused"} end)

      assert {:ok, []} = ModelCache.get_models()
    end
  end

  describe "clear/0" do
    test "clears the cache forcing a fresh fetch" do
      models_v1 = [
        %{"id" => "ollama/model-v1", "name" => "model-v1", "provider" => "ollama"}
      ]

      models_v2 = [
        %{"id" => "ollama/model-v2", "name" => "model-v2", "provider" => "ollama"}
      ]

      # First call caches
      expect_ollama_models(models_v1)

      assert {:ok, ^models_v1} = ModelCache.get_models()

      # Clear the cache
      ModelCache.clear()
      Process.sleep(10)

      # Next call should fetch fresh
      expect_ollama_models(models_v2)

      assert {:ok, ^models_v2} = ModelCache.get_models()
    end
  end

  describe "refresh/0" do
    test "refreshes the cache with new data" do
      models_v1 = [
        %{"id" => "ollama/model-v1", "name" => "model-v1", "provider" => "ollama"}
      ]

      models_v2 = [
        %{"id" => "ollama/model-v2", "name" => "model-v2", "provider" => "ollama"}
      ]

      # First call caches
      expect_ollama_models(models_v1)

      assert {:ok, ^models_v1} = ModelCache.get_models()

      # Refresh should fetch new models
      expect_ollama_models(models_v2)

      ModelCache.refresh()
      # Wait for the async refresh to complete
      Process.sleep(20)

      # Now get_models should return the refreshed data (no API call)
      assert {:ok, ^models_v2} = ModelCache.get_models()
    end
  end
end
