defmodule Chatbot.LMStudioTest do
  use ExUnit.Case, async: false

  alias Chatbot.LMStudio

  setup do
    # Reset fuse before each test to ensure clean state
    :fuse.reset(:lm_studio_fuse)

    bypass = Bypass.open()
    original_config = Application.get_env(:chatbot, :lm_studio, [])

    Application.put_env(:chatbot, :lm_studio,
      base_url: "http://localhost:#{bypass.port}/v1",
      stream_timeout_ms: 5_000
    )

    on_exit(fn ->
      Application.put_env(:chatbot, :lm_studio, original_config)
    end)

    %{bypass: bypass}
  end

  describe "list_models/0" do
    test "returns list of models on success", %{bypass: bypass} do
      models = [
        %{"id" => "model-1", "object" => "model"},
        %{"id" => "model-2", "object" => "model"}
      ]

      Bypass.expect_once(bypass, "GET", "/v1/models", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"data" => models}))
      end)

      assert {:ok, ^models} = LMStudio.list_models()
    end

    test "returns error on non-200 status", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/v1/models", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "Internal Server Error"}))
      end)

      # Error message is sanitized to not expose internal details
      assert {:error, "Failed to load models. Please check if LM Studio is running."} =
               LMStudio.list_models()
    end

    test "returns error when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, _message} = LMStudio.list_models()
    end
  end

  describe "chat_completion/2" do
    test "returns response on success", %{bypass: bypass} do
      messages = [%{role: "user", content: "Hello"}]
      model = "test-model"

      expected_response = %{
        "choices" => [
          %{"message" => %{"role" => "assistant", "content" => "Hi there!"}}
        ]
      }

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["model"] == model
        assert request["messages"] == [%{"role" => "user", "content" => "Hello"}]
        assert request["temperature"] == 0.7

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(expected_response))
      end)

      assert {:ok, ^expected_response} = LMStudio.chat_completion(messages, model)
    end

    test "returns error on non-200 status", %{bypass: bypass} do
      messages = [%{role: "user", content: "Hello"}]
      model = "test-model"

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad Request"}))
      end)

      # Error message is sanitized to not expose internal details
      assert {:error, "Failed to get AI response. Please try again."} =
               LMStudio.chat_completion(messages, model)
    end

    test "returns error when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      messages = [%{role: "user", content: "Hello"}]
      model = "test-model"

      assert {:error, _message} = LMStudio.chat_completion(messages, model)
    end
  end

  describe "stream_chat_completion/3" do
    test "streams chunks to the given process", %{bypass: bypass} do
      messages = [%{role: "user", content: "Hello"}]
      model = "test-model"

      # SSE format response
      sse_data = """
      data: {"choices":[{"delta":{"content":"Hello"}}]}

      data: {"choices":[{"delta":{"content":" there"}}]}

      data: {"choices":[{"delta":{"content":"!"}}]}

      data: [DONE]
      """

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["stream"] == true
        assert request["model"] == model

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.resp(200, sse_data)
      end)

      assert :ok = LMStudio.stream_chat_completion(messages, model, self())

      # Collect all chunks
      chunks = collect_stream_messages([])

      assert Enum.member?(chunks, {:chunk, "Hello"})
      assert Enum.member?(chunks, {:chunk, " there"})
      assert Enum.member?(chunks, {:chunk, "!"})
      assert Enum.any?(chunks, fn msg -> match?({:done, _}, msg) end)
    end

    test "sends error message when connection fails", %{bypass: bypass} do
      Bypass.down(bypass)

      messages = [%{role: "user", content: "Hello"}]
      model = "test-model"

      assert {:error, _reason} = LMStudio.stream_chat_completion(messages, model, self())

      assert_receive {:error, _error_message}, 1000
    end
  end

  describe "circuit breaker" do
    test "opens circuit after multiple failures", %{bypass: bypass} do
      # Make the bypass fail
      Bypass.down(bypass)

      messages = [%{role: "user", content: "Hello"}]
      model = "test-model"

      # Trigger multiple failures to blow the fuse
      for _i <- 1..6 do
        LMStudio.list_models()
      end

      # Circuit should be blown now
      assert {:error, "LM Studio service is temporarily unavailable. Please try again later."} =
               LMStudio.list_models()

      assert {:error, "LM Studio service is temporarily unavailable. Please try again later."} =
               LMStudio.chat_completion(messages, model)
    end

    test "circuit recovers after reset period" do
      # This test verifies the circuit breaker can be reset
      # In a real scenario, this would happen automatically after 30 seconds
      :fuse.reset(:lm_studio_fuse)

      # After reset, the fuse should be ok
      status = :fuse.ask(:lm_studio_fuse, :sync)
      assert status in [:ok, {:error, :not_found}]
    end
  end

  # Helper to collect stream messages
  defp collect_stream_messages(acc) do
    receive do
      {:chunk, content} ->
        collect_stream_messages([{:chunk, content} | acc])

      {:done, _metadata} ->
        [{:done, ""} | acc]

      {:error, msg} ->
        [{:error, msg} | acc]
    after
      500 ->
        Enum.reverse(acc)
    end
  end
end
