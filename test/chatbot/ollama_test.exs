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
