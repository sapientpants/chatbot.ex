defmodule Chatbot.ModelCacheTest do
  use ExUnit.Case, async: false

  import Mox

  alias Chatbot.ModelCache

  # Use global mode for Mox since ModelCache is a GenServer
  # that runs in a separate process
  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Configure test to use the mock
    Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)
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
      Application.put_env(:chatbot, :model_cache, ttl_ms: 60_000)
    end)

    :ok
  end

  describe "get_models/0" do
    test "fetches models from LMStudio on cache miss" do
      models = [%{"id" => "test-model", "object" => "model"}]

      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models} end)

      assert {:ok, ^models} = ModelCache.get_models()
    end

    test "returns cached models on cache hit" do
      models = [%{"id" => "cached-model", "object" => "model"}]

      # First call fetches from API
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models} end)

      assert {:ok, ^models} = ModelCache.get_models()

      # Second call should use cache (no additional API call expected)
      assert {:ok, ^models} = ModelCache.get_models()
    end

    test "fetches new models after TTL expires" do
      models_v1 = [%{"id" => "model-v1", "object" => "model"}]
      models_v2 = [%{"id" => "model-v2", "object" => "model"}]

      # First call
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models_v1} end)

      assert {:ok, ^models_v1} = ModelCache.get_models()

      # Wait for TTL to expire (50ms + buffer)
      Process.sleep(60)

      # Second call should fetch fresh data
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models_v2} end)

      assert {:ok, ^models_v2} = ModelCache.get_models()
    end

    test "returns error when LMStudio fails" do
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:error, "Connection refused"} end)

      assert {:error, "Connection refused"} = ModelCache.get_models()
    end
  end

  describe "clear/0" do
    test "clears the cache forcing a fresh fetch" do
      models_v1 = [%{"id" => "model-v1", "object" => "model"}]
      models_v2 = [%{"id" => "model-v2", "object" => "model"}]

      # First call caches
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models_v1} end)

      assert {:ok, ^models_v1} = ModelCache.get_models()

      # Clear the cache
      ModelCache.clear()
      Process.sleep(10)

      # Next call should fetch fresh
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models_v2} end)

      assert {:ok, ^models_v2} = ModelCache.get_models()
    end
  end

  describe "refresh/0" do
    test "refreshes the cache with new data" do
      models_v1 = [%{"id" => "model-v1", "object" => "model"}]
      models_v2 = [%{"id" => "model-v2", "object" => "model"}]

      # First call caches
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models_v1} end)

      assert {:ok, ^models_v1} = ModelCache.get_models()

      # Refresh should fetch new models
      Chatbot.LMStudioMock
      |> expect(:list_models, fn -> {:ok, models_v2} end)

      ModelCache.refresh()
      # Wait for the async refresh to complete
      Process.sleep(20)

      # Now get_models should return the refreshed data (no API call)
      assert {:ok, ^models_v2} = ModelCache.get_models()
    end
  end
end
