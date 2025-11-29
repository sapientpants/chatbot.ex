defmodule Chatbot.Ollama do
  @moduledoc """
  Client for interacting with Ollama's API for embeddings and chat completions.

  Configuration is loaded from application config under `:chatbot, :ollama`.
  Includes circuit breaker protection using Fuse to prevent cascading failures.

  ## Configuration

      config :chatbot, :ollama,
        base_url: "http://localhost:11434",
        embedding_model: "qwen3-embedding:0.6b",
        embedding_dimension: 1024,
        timeout_ms: 30_000,
        stream_timeout_ms: 300_000

  ## Chat API

  Ollama uses NDJSON (newline-delimited JSON) for streaming, not SSE:

      {"message": {"content": "token"}, "done": false}
      {"message": {"content": ""}, "done": true}

  """

  @behaviour Chatbot.OllamaBehaviour

  require Logger

  @typedoc "A chat message in OpenAI format"
  @type message :: %{role: String.t(), content: String.t()}

  @typedoc "A list of chat messages"
  @type messages :: [message()]

  @typedoc "Model information from Ollama"
  @type model_info :: %{String.t() => any()}

  @fuse_name :ollama_fuse

  # Circuit breaker configuration:
  # - Max 5 failures within 60 seconds opens the circuit
  # - Circuit attempts reset after 30 seconds
  @fuse_max_failures 5
  @fuse_window_ms 60_000
  @fuse_reset_ms 30_000
  @fuse_options {{:standard, @fuse_max_failures, @fuse_window_ms}, {:reset, @fuse_reset_ms}}

  @provider_prefix "ollama/"

  defp base_url do
    config()[:base_url] || "http://localhost:11434"
  end

  defp embedding_model do
    config()[:embedding_model] || "qwen3-embedding:0.6b"
  end

  defp timeout do
    config()[:timeout_ms] || 30_000
  end

  defp stream_timeout do
    config()[:stream_timeout_ms] || 300_000
  end

  defp config do
    Application.get_env(:chatbot, :ollama, [])
  end

  @doc """
  Strips the provider prefix from a model name.

  ## Examples

      iex> strip_provider_prefix("ollama/llama3")
      "llama3"

      iex> strip_provider_prefix("llama3")
      "llama3"

  """
  @spec strip_provider_prefix(String.t()) :: String.t()
  def strip_provider_prefix(model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      ["ollama", name] -> name
      _other -> model
    end
  end

  defp ensure_fuse_installed do
    case :fuse.ask(@fuse_name, :sync) do
      :ok ->
        :ok

      :blown ->
        :blown

      {:error, :not_found} ->
        :fuse.install(@fuse_name, @fuse_options)
        :ok
    end
  end

  defp with_circuit_breaker(fun) do
    case ensure_fuse_installed() do
      :blown ->
        {:error, "Ollama service is temporarily unavailable. Please try again later."}

      :ok ->
        result = fun.()

        case result do
          {:error, _reason} ->
            :fuse.melt(@fuse_name)
            result

          _success ->
            result
        end
    end
  end

  @doc """
  Returns the configured embedding dimension.

  ## Examples

      iex> embedding_dimension()
      1024

  """
  @impl Chatbot.OllamaBehaviour
  @spec embedding_dimension() :: pos_integer()
  def embedding_dimension do
    config()[:embedding_dimension] || 1024
  end

  @doc """
  Generates an embedding vector for the given text.
  Protected by circuit breaker to prevent cascading failures.

  ## Parameters
    - text: The text to generate an embedding for

  ## Returns
    - `{:ok, embedding}` where embedding is a list of floats
    - `{:error, reason}` on failure

  ## Examples

      iex> embed("Hello, world!")
      {:ok, [0.123, -0.456, ...]}

      iex> embed("test")
      {:error, "Failed to connect to Ollama"}

  """
  @impl Chatbot.OllamaBehaviour
  @spec embed(String.t()) :: {:ok, [float()]} | {:error, String.t()}
  def embed(text) when is_binary(text) do
    with_circuit_breaker(fn ->
      body = %{
        model: embedding_model(),
        input: text
      }

      case Req.post("#{base_url()}/api/embed",
             json: body,
             receive_timeout: timeout(),
             retry: false
           ) do
        {:ok, %{status: 200, body: %{"embeddings" => [embedding | _rest]}}} ->
          {:ok, embedding}

        {:ok, %{status: 200, body: %{"embeddings" => []}}} ->
          Logger.warning("Ollama returned empty embeddings list")
          {:error, "No embedding returned by Ollama for the given input."}

        {:ok, %{status: 200, body: %{"embedding" => embedding}}} ->
          # Fallback for older API format
          {:ok, embedding}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Ollama embed request failed: status=#{status}, body=#{inspect(body)}")
          {:error, "Failed to generate embedding. Please check if Ollama is running."}

        {:error, exception} ->
          Logger.warning("Ollama embed request error: #{Exception.message(exception)}")
          {:error, "Failed to connect to Ollama. Please check if it is running."}
      end
    end)
  end

  @doc """
  Generates embedding vectors for multiple texts in a single request.
  Protected by circuit breaker to prevent cascading failures.

  ## Parameters
    - texts: List of texts to generate embeddings for

  ## Returns
    - `{:ok, embeddings}` where embeddings is a list of embedding vectors
    - `{:error, reason}` on failure

  ## Examples

      iex> embed_batch(["Hello", "World"])
      {:ok, [[0.123, ...], [0.456, ...]]}

  """
  @impl Chatbot.OllamaBehaviour
  @spec embed_batch([String.t()]) :: {:ok, [[float()]]} | {:error, String.t()}
  def embed_batch(texts) when is_list(texts) do
    with_circuit_breaker(fn ->
      body = %{
        model: embedding_model(),
        input: texts
      }

      case Req.post("#{base_url()}/api/embed",
             json: body,
             receive_timeout: timeout(),
             retry: false
           ) do
        {:ok, %{status: 200, body: %{"embeddings" => embeddings}}} when is_list(embeddings) ->
          {:ok, embeddings}

        {:ok, %{status: status, body: body}} ->
          Logger.warning(
            "Ollama batch embed request failed: status=#{status}, body=#{inspect(body)}"
          )

          {:error, "Failed to generate embeddings. Please check if Ollama is running."}

        {:error, exception} ->
          Logger.warning("Ollama batch embed request error: #{Exception.message(exception)}")
          {:error, "Failed to connect to Ollama. Please check if it is running."}
      end
    end)
  end

  # ============================================================================
  # Chat Completion Functions
  # ============================================================================

  @doc """
  Fetches the list of available models from Ollama.
  Protected by circuit breaker to prevent cascading failures.

  Models are returned with the `ollama/` prefix for provider identification.

  ## Examples

      iex> list_models()
      {:ok, [%{"id" => "ollama/llama3", "name" => "llama3", ...}]}

      iex> list_models()
      {:error, "Failed to connect to Ollama"}

  """
  @impl Chatbot.OllamaBehaviour
  @spec list_models() :: {:ok, [model_info()]} | {:error, String.t()}
  def list_models do
    with_circuit_breaker(fn ->
      case Req.get("#{base_url()}/api/tags", receive_timeout: timeout(), retry: false) do
        {:ok, %{status: 200, body: %{"models" => models}}} ->
          prefixed_models =
            Enum.map(models, fn model ->
              name = model["name"] || model["model"]

              %{
                "id" => @provider_prefix <> name,
                "name" => name,
                "provider" => "ollama",
                "size" => model["size"],
                "modified_at" => model["modified_at"]
              }
            end)

          {:ok, prefixed_models}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Ollama models request failed: status=#{status}, body=#{inspect(body)}")
          {:error, "Failed to load models. Please check if Ollama is running."}

        {:error, exception} ->
          Logger.warning("Ollama models request error: #{Exception.message(exception)}")
          {:error, "Failed to connect to Ollama. Please check if it is running."}
      end
    end)
  end

  @doc """
  Sends a non-streaming chat completion request.
  Protected by circuit breaker to prevent cascading failures.

  ## Parameters
    - messages: List of messages in OpenAI format
    - model: Model name to use (with or without `ollama/` prefix)

  ## Returns
    - `{:ok, response}` with the completion response in OpenAI-compatible format
    - `{:error, reason}` on failure

  ## Examples

      iex> chat_completion([%{role: "user", content: "Hello"}], "ollama/llama3")
      {:ok, %{"choices" => [%{"message" => %{"content" => "Hi there!"}}]}}

  """
  @impl Chatbot.OllamaBehaviour
  @spec chat_completion(messages(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_completion(messages, model) do
    with_circuit_breaker(fn ->
      # Strip provider prefix if present
      model_name = strip_provider_prefix(model)

      body = %{
        model: model_name,
        messages: messages,
        stream: false
      }

      case Req.post("#{base_url()}/api/chat",
             json: body,
             receive_timeout: timeout(),
             retry: false
           ) do
        {:ok, %{status: 200, body: %{"message" => message} = response}} ->
          # Convert Ollama response to OpenAI-compatible format
          openai_response = %{
            "choices" => [
              %{
                "index" => 0,
                "message" => %{
                  "role" => message["role"] || "assistant",
                  "content" => message["content"] || ""
                },
                "finish_reason" => if(response["done"], do: "stop", else: nil)
              }
            ],
            "model" => model_name,
            "usage" => %{
              "prompt_tokens" => response["prompt_eval_count"] || 0,
              "completion_tokens" => response["eval_count"] || 0,
              "total_tokens" =>
                (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
            }
          }

          {:ok, openai_response}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Ollama chat completion failed: status=#{status}, body=#{inspect(body)}")

          {:error, "Failed to get AI response. Please try again."}

        {:error, exception} ->
          Logger.warning("Ollama chat completion error: #{Exception.message(exception)}")
          {:error, "Failed to connect to Ollama. Please check if it is running."}
      end
    end)
  end

  @doc """
  Sends a chat completion request with streaming enabled.
  Protected by circuit breaker to prevent cascading failures.

  Ollama uses NDJSON (newline-delimited JSON) for streaming responses.

  ## Parameters
    - messages: List of messages in OpenAI format [%{role: "user", content: "..."}]
    - model: Model name to use (with or without `ollama/` prefix)
    - pid: Process ID to send streaming chunks to

  ## Messages sent to pid
    - `{:chunk, content}` - A token chunk
    - `{:done, ""}` - Streaming complete
    - `{:error, reason}` - An error occurred

  ## Examples

      iex> stream_chat_completion([%{role: "user", content: "Hello"}], "ollama/llama3", self())
      :ok

  """
  @impl Chatbot.OllamaBehaviour
  @spec stream_chat_completion(messages(), String.t(), pid()) :: :ok | {:error, String.t()}
  def stream_chat_completion(messages, model, pid) do
    # Check circuit breaker first
    case ensure_fuse_installed() do
      :blown ->
        error_msg = "Ollama service is temporarily unavailable. Please try again later."
        send(pid, {:error, error_msg})
        {:error, error_msg}

      :ok ->
        do_stream_chat_completion(messages, model, pid)
    end
  end

  defp do_stream_chat_completion(messages, model, pid) do
    # Strip provider prefix if present
    model_name = strip_provider_prefix(model)

    body = %{
      model: model_name,
      messages: messages,
      stream: true
    }

    # Custom Finch streaming function to handle NDJSON
    finch_stream = fn request, finch_request, finch_name, finch_options ->
      # Buffer for incomplete JSON lines
      buffer = ""

      stream_handler = fn
        {:status, status}, {response, buf} ->
          {%{response | status: status}, buf}

        {:headers, headers}, {response, buf} ->
          {%{response | headers: headers}, buf}

        {:data, data}, {response, buf} ->
          # Combine buffer with new data and process complete lines
          combined = buf <> data
          {remaining, _ok} = process_ndjson_data(combined, pid)
          {response, remaining}
      end

      case Finch.stream(
             finch_request,
             finch_name,
             {Req.Response.new(), buffer},
             stream_handler,
             finch_options
           ) do
        {:ok, {response, _remaining_buffer}} ->
          send(pid, {:done, ""})
          {request, response}

        {:error, reason} ->
          Logger.warning("Finch stream error: #{inspect(reason)}")
          send(pid, {:error, "Failed to get AI response. Please try again."})
          raise "Finch streaming failed: #{inspect(reason)}"
      end
    end

    try do
      Req.post!("#{base_url()}/api/chat",
        json: body,
        receive_timeout: stream_timeout(),
        finch_request: finch_stream,
        retry: false
      )

      :ok
    rescue
      e ->
        # Record failure in circuit breaker
        :fuse.melt(@fuse_name)
        Logger.warning("Ollama streaming error: #{Exception.message(e)}")
        error_msg = "Failed to get AI response. Please try again."
        send(pid, {:error, error_msg})
        {:error, error_msg}
    end
  end

  # Process NDJSON data, handling incomplete lines
  defp process_ndjson_data(data, pid) do
    lines = String.split(data, "\n")

    # The last element might be incomplete if we're mid-stream
    {complete_lines, remaining} =
      case List.last(lines) do
        "" -> {Enum.drop(lines, -1), ""}
        incomplete -> {Enum.drop(lines, -1), incomplete}
      end

    Enum.each(complete_lines, fn line ->
      process_ndjson_line(String.trim(line), pid)
    end)

    {remaining, :ok}
  end

  defp process_ndjson_line("", _pid), do: :ok

  defp process_ndjson_line(json_string, pid) do
    case Jason.decode(json_string) do
      {:ok, %{"message" => %{"content" => content}, "done" => false}} when content != "" ->
        send(pid, {:chunk, content})

      {:ok, %{"done" => true}} ->
        :ok

      {:ok, _other} ->
        :ok

      {:error, _reason} ->
        Logger.debug("Failed to parse Ollama NDJSON line: #{json_string}")
        :ok
    end
  end
end
