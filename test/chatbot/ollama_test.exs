defmodule Chatbot.OllamaTest do
  use ExUnit.Case, async: false

  alias Chatbot.Ollama

  setup do
    # Reset fuse before each test to ensure clean state
    :fuse.reset(:ollama_fuse)

    bypass = Bypass.open()
    original_config = Application.get_env(:chatbot, :ollama, [])

    Application.put_env(:chatbot, :ollama,
      base_url: "http://localhost:#{bypass.port}",
      embedding_model: "qwen3-embedding:0.6b",
      embedding_dimension: 1024,
      timeout_ms: 5_000
    )

    on_exit(fn ->
      Application.put_env(:chatbot, :ollama, original_config)
    end)

    %{bypass: bypass}
  end

  describe "embedding_dimension/0" do
    test "returns configured dimension" do
      assert Ollama.embedding_dimension() == 1024
    end
  end

  describe "embed/1" do
    test "returns embedding on success", %{bypass: bypass} do
      embedding = List.duplicate(0.1, 1024)

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["model"] == "qwen3-embedding:0.6b"
        assert request["input"] == "Hello, world!"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"embeddings" => [embedding]}))
      end)

      assert {:ok, ^embedding} = Ollama.embed("Hello, world!")
    end

    test "handles legacy API format with 'embedding' key", %{bypass: bypass} do
      embedding = List.duplicate(0.2, 1024)

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"embedding" => embedding}))
      end)

      assert {:ok, ^embedding} = Ollama.embed("test text")
    end

    test "returns error on non-200 status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "Internal Server Error"}))
      end)

      assert {:error, "Failed to generate embedding. Please check if Ollama is running."} =
               Ollama.embed("test")
    end

    test "returns error when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, _message} = Ollama.embed("test")
    end
  end

  describe "embed_batch/1" do
    test "returns embeddings for multiple texts", %{bypass: bypass} do
      embeddings = [
        List.duplicate(0.1, 1024),
        List.duplicate(0.2, 1024),
        List.duplicate(0.3, 1024)
      ]

      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["model"] == "qwen3-embedding:0.6b"
        assert request["input"] == ["Hello", "World", "Test"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"embeddings" => embeddings}))
      end)

      assert {:ok, ^embeddings} = Ollama.embed_batch(["Hello", "World", "Test"])
    end

    test "returns error on non-200 status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/embed", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad Request"}))
      end)

      assert {:error, "Failed to generate embeddings. Please check if Ollama is running."} =
               Ollama.embed_batch(["test1", "test2"])
    end

    test "returns error when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, _message} = Ollama.embed_batch(["test"])
    end
  end

  describe "strip_provider_prefix/1" do
    test "strips ollama/ prefix" do
      assert Ollama.strip_provider_prefix("ollama/llama3") == "llama3"
    end

    test "preserves model name without prefix" do
      assert Ollama.strip_provider_prefix("llama3") == "llama3"
    end

    test "preserves model name with other prefix" do
      assert Ollama.strip_provider_prefix("lmstudio/mistral") == "lmstudio/mistral"
    end
  end

  describe "list_models/0" do
    test "returns models with ollama/ prefix", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        response = %{
          "models" => [
            %{
              "name" => "llama3",
              "size" => 4_000_000_000,
              "modified_at" => "2024-01-01T00:00:00Z"
            },
            %{
              "name" => "mistral",
              "size" => 3_000_000_000,
              "modified_at" => "2024-01-02T00:00:00Z"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, models} = Ollama.list_models()
      assert length(models) == 2
      assert Enum.at(models, 0)["id"] == "ollama/llama3"
      assert Enum.at(models, 0)["provider"] == "ollama"
      assert Enum.at(models, 1)["id"] == "ollama/mistral"
    end

    test "returns error on non-200 status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "Internal Server Error"}))
      end)

      assert {:error, _msg} = Ollama.list_models()
    end

    test "returns error when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, _msg} = Ollama.list_models()
    end
  end

  describe "chat_completion/2" do
    test "returns OpenAI-compatible response on success", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["model"] == "llama3"
        assert request["stream"] == false
        assert length(request["messages"]) == 1

        response = %{
          "message" => %{"role" => "assistant", "content" => "Hello!"},
          "done" => true,
          "prompt_eval_count" => 10,
          "eval_count" => 5
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      messages = [%{role: "user", content: "Hi"}]
      assert {:ok, response} = Ollama.chat_completion(messages, "ollama/llama3")
      assert response["choices"]
      assert Enum.at(response["choices"], 0)["message"]["content"] == "Hello!"
      assert response["usage"]["total_tokens"] == 15
    end

    test "strips provider prefix from model", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        # Verify the prefix was stripped
        assert request["model"] == "llama3"

        response = %{
          "message" => %{"role" => "assistant", "content" => "Hi!"},
          "done" => true
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, _response} = Ollama.chat_completion(messages, "ollama/llama3")
    end

    test "returns error on non-200 status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "Model not found"}))
      end)

      messages = [%{role: "user", content: "Hi"}]
      assert {:error, _msg} = Ollama.chat_completion(messages, "llama3")
    end

    test "returns error when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      messages = [%{role: "user", content: "Hi"}]
      assert {:error, _msg} = Ollama.chat_completion(messages, "llama3")
    end
  end

  describe "stream_chat_completion/3" do
    test "sends chunks to process", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["model"] == "llama3"
        assert request["stream"] == true

        # NDJSON streaming response
        chunks = [
          %{"message" => %{"content" => "Hello"}, "done" => false},
          %{"message" => %{"content" => " there"}, "done" => false},
          %{"message" => %{"content" => ""}, "done" => true}
        ]

        ndjson = Enum.map_join(chunks, "\n", &Jason.encode!/1)

        conn
        |> Plug.Conn.put_resp_content_type("application/x-ndjson")
        |> Plug.Conn.resp(200, ndjson)
      end)

      messages = [%{role: "user", content: "Hi"}]
      assert :ok = Ollama.stream_chat_completion(messages, "ollama/llama3", self())

      # Should receive chunks
      assert_receive {:chunk, "Hello"}, 1000
      assert_receive {:chunk, " there"}, 1000
      assert_receive {:done, ""}, 1000
    end

    test "sends error when circuit breaker is blown", %{bypass: bypass} do
      Bypass.down(bypass)

      # Blow the circuit
      for _i <- 1..6 do
        Ollama.embed("test")
      end

      messages = [%{role: "user", content: "Hi"}]
      result = Ollama.stream_chat_completion(messages, "llama3", self())

      assert {:error, "Ollama service is temporarily unavailable. Please try again later."} =
               result

      assert_receive {:error,
                      "Ollama service is temporarily unavailable. Please try again later."},
                     1000
    end
  end

  describe "circuit breaker" do
    test "opens circuit after multiple failures", %{bypass: bypass} do
      Bypass.down(bypass)

      # Trigger multiple failures to blow the fuse
      for _i <- 1..6 do
        Ollama.embed("test")
      end

      # Circuit should be blown now
      assert {:error, "Ollama service is temporarily unavailable. Please try again later."} =
               Ollama.embed("test")

      assert {:error, "Ollama service is temporarily unavailable. Please try again later."} =
               Ollama.embed_batch(["test"])
    end

    test "circuit recovers after reset" do
      :fuse.reset(:ollama_fuse)

      status = :fuse.ask(:ollama_fuse, :sync)
      assert status in [:ok, {:error, :not_found}]
    end
  end
end
