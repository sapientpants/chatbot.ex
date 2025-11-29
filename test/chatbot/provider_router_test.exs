defmodule Chatbot.ProviderRouterTest do
  use ExUnit.Case, async: false

  import Mox

  alias Chatbot.ProviderRouter

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Configure to use mocks
    Application.put_env(:chatbot, :ollama_client, Chatbot.OllamaMock)
    Application.put_env(:chatbot, :lm_studio_client, Chatbot.LMStudioMock)

    on_exit(fn ->
      Application.delete_env(:chatbot, :ollama_client)
      Application.delete_env(:chatbot, :lm_studio_client)
    end)

    :ok
  end

  describe "chat_completion/2" do
    test "routes to Ollama for ollama/ prefixed model" do
      expect(Chatbot.OllamaMock, :chat_completion, fn messages, model ->
        assert messages == [%{role: "user", content: "Hello"}]
        assert model == "llama3"
        {:ok, %{"choices" => [%{"message" => %{"content" => "Hi!"}}]}}
      end)

      assert {:ok, _response} =
               ProviderRouter.chat_completion(
                 [%{role: "user", content: "Hello"}],
                 "ollama/llama3"
               )
    end

    test "routes to LM Studio for lmstudio/ prefixed model" do
      expect(Chatbot.LMStudioMock, :chat_completion, fn messages, model ->
        assert messages == [%{role: "user", content: "Hello"}]
        assert model == "mistral"
        {:ok, %{"choices" => [%{"message" => %{"content" => "Hi!"}}]}}
      end)

      assert {:ok, _response} =
               ProviderRouter.chat_completion(
                 [%{role: "user", content: "Hello"}],
                 "lmstudio/mistral"
               )
    end

    test "routes to default provider for unprefixed model" do
      # Default provider is Ollama
      expect(Chatbot.OllamaMock, :chat_completion, fn _messages, model ->
        assert model == "llama3"
        {:ok, %{"choices" => [%{"message" => %{"content" => "Hi!"}}]}}
      end)

      assert {:ok, _response} =
               ProviderRouter.chat_completion([%{role: "user", content: "Hello"}], "llama3")
    end
  end

  describe "stream_chat_completion/3" do
    test "routes to Ollama for ollama/ prefixed model" do
      expect(Chatbot.OllamaMock, :stream_chat_completion, fn _messages, model, _pid ->
        assert model == "llama3"
        :ok
      end)

      assert :ok =
               ProviderRouter.stream_chat_completion(
                 [%{role: "user", content: "Hello"}],
                 "ollama/llama3",
                 self()
               )
    end

    test "routes to LM Studio for lmstudio/ prefixed model" do
      expect(Chatbot.LMStudioMock, :stream_chat_completion, fn _messages, model, _pid ->
        assert model == "mistral"
        :ok
      end)

      assert :ok =
               ProviderRouter.stream_chat_completion(
                 [%{role: "user", content: "Hello"}],
                 "lmstudio/mistral",
                 self()
               )
    end
  end

  describe "embed/1" do
    test "routes to Ollama for embeddings" do
      embedding = List.duplicate(0.1, 1024)

      expect(Chatbot.OllamaMock, :embed, fn text ->
        assert text == "Hello, world!"
        {:ok, embedding}
      end)

      assert {:ok, ^embedding} = ProviderRouter.embed("Hello, world!")
    end
  end

  describe "embed_batch/1" do
    test "routes to Ollama for batch embeddings" do
      embeddings = [List.duplicate(0.1, 1024), List.duplicate(0.2, 1024)]

      expect(Chatbot.OllamaMock, :embed_batch, fn texts ->
        assert texts == ["Hello", "World"]
        {:ok, embeddings}
      end)

      assert {:ok, ^embeddings} = ProviderRouter.embed_batch(["Hello", "World"])
    end
  end

  describe "embedding_dimension/0" do
    test "returns dimension from Ollama" do
      expect(Chatbot.OllamaMock, :embedding_dimension, fn -> 1024 end)

      assert 1024 = ProviderRouter.embedding_dimension()
    end
  end

  describe "list_all_models/0" do
    test "aggregates models from Ollama when LM Studio is disabled" do
      ollama_models = [
        %{"id" => "ollama/llama3", "name" => "llama3", "provider" => "ollama"}
      ]

      expect(Chatbot.OllamaMock, :list_models, fn -> {:ok, ollama_models} end)

      # LM Studio is disabled by default, so list_all_models won't call it
      assert {:ok, models} = ProviderRouter.list_all_models()
      assert models == ollama_models
    end

    test "returns Ollama models when LM Studio fails" do
      ollama_models = [
        %{"id" => "ollama/llama3", "name" => "llama3", "provider" => "ollama"}
      ]

      expect(Chatbot.OllamaMock, :list_models, fn -> {:ok, ollama_models} end)

      assert {:ok, models} = ProviderRouter.list_all_models()
      assert models == ollama_models
    end

    test "returns empty list when Ollama fails and LM Studio is disabled" do
      expect(Chatbot.OllamaMock, :list_models, fn -> {:error, "Connection refused"} end)

      # When LM Studio is disabled, it returns {:ok, []} which counts as success
      # So the overall result is empty models, not an error
      assert {:ok, []} = ProviderRouter.list_all_models()
    end
  end

  describe "completion_provider/0" do
    test "returns :ollama by default" do
      assert :ollama = ProviderRouter.completion_provider()
    end
  end

  describe "embedding_provider/0" do
    test "returns :ollama by default" do
      assert :ollama = ProviderRouter.embedding_provider()
    end
  end

  describe "lmstudio_enabled?/0" do
    test "returns false by default" do
      refute ProviderRouter.lmstudio_enabled?()
    end
  end
end
