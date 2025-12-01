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

  """

  @behaviour Chatbot.OllamaBehaviour

  alias Chatbot.CircuitBreaker
  alias Chatbot.Ollama.ResponseFormatter
  alias Chatbot.Ollama.Streaming

  require Logger

  @typedoc "A chat message in OpenAI format"
  @type message :: %{role: String.t(), content: String.t()}

  @typedoc "A list of chat messages"
  @type messages :: [message()]

  @typedoc "Model information from Ollama"
  @type model_info :: %{String.t() => any()}

  @fuse_name :ollama_fuse
  @fuse_opts [max_failures: 5, window_ms: 60_000, reset_ms: 30_000]
  @provider_prefix "ollama/"

  # Configuration helpers

  defp base_url do
    config()[:base_url] || settings_url() || "http://localhost:11434"
  end

  defp embedding_model do
    config()[:embedding_model] || settings_embedding_model() || "qwen3-embedding:0.6b"
  end

  defp settings_url do
    Chatbot.Settings.get("ollama_url")
  rescue
    ArgumentError -> nil
  end

  defp settings_embedding_model do
    Chatbot.Settings.get("ollama_embedding_model")
  rescue
    ArgumentError -> nil
  end

  defp timeout, do: config()[:timeout_ms] || 30_000
  defp stream_timeout, do: config()[:stream_timeout_ms] || 300_000
  defp config, do: Application.get_env(:chatbot, :ollama, [])

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

  @doc """
  Returns the configured embedding dimension.
  """
  @impl Chatbot.OllamaBehaviour
  @spec embedding_dimension() :: pos_integer()
  def embedding_dimension, do: config()[:embedding_dimension] || 1024

  # ============================================================================
  # Embedding Functions
  # ============================================================================

  @doc """
  Generates an embedding vector for the given text.
  Protected by circuit breaker to prevent cascading failures.
  """
  @impl Chatbot.OllamaBehaviour
  @spec embed(String.t()) :: {:ok, [float()]} | {:error, String.t()}
  def embed(text) when is_binary(text) do
    @fuse_name
    |> CircuitBreaker.with_fuse(fn -> do_embed(text) end, @fuse_opts)
    |> handle_circuit_error("Ollama")
  end

  defp do_embed(text) do
    body = %{model: embedding_model(), input: text}

    case Req.post("#{base_url()}/api/embed", json: body, receive_timeout: timeout(), retry: false) do
      {:ok, %{status: 200, body: %{"embeddings" => [embedding | _rest]}}} ->
        {:ok, embedding}

      {:ok, %{status: 200, body: %{"embeddings" => []}}} ->
        Logger.warning("Ollama returned empty embeddings list")
        {:error, "No embedding returned by Ollama for the given input."}

      {:ok, %{status: 200, body: %{"embedding" => embedding}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama embed request failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to generate embedding. Please check if Ollama is running."}

      {:error, exception} ->
        Logger.warning("Ollama embed request error: #{Exception.message(exception)}")
        {:error, "Failed to connect to Ollama. Please check if it is running."}
    end
  end

  @doc """
  Generates embedding vectors for multiple texts in a single request.
  """
  @impl Chatbot.OllamaBehaviour
  @spec embed_batch([String.t()]) :: {:ok, [[float()]]} | {:error, String.t()}
  def embed_batch(texts) when is_list(texts) do
    @fuse_name
    |> CircuitBreaker.with_fuse(fn -> do_embed_batch(texts) end, @fuse_opts)
    |> handle_circuit_error("Ollama")
  end

  defp do_embed_batch(texts) do
    body = %{model: embedding_model(), input: texts}

    case Req.post("#{base_url()}/api/embed", json: body, receive_timeout: timeout(), retry: false) do
      {:ok, %{status: 200, body: %{"embeddings" => embeddings}}} when is_list(embeddings) ->
        {:ok, embeddings}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama batch embed failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to generate embeddings. Please check if Ollama is running."}

      {:error, exception} ->
        Logger.warning("Ollama batch embed error: #{Exception.message(exception)}")
        {:error, "Failed to connect to Ollama. Please check if it is running."}
    end
  end

  # ============================================================================
  # Chat Completion Functions
  # ============================================================================

  @doc """
  Fetches the list of available models from Ollama.
  """
  @impl Chatbot.OllamaBehaviour
  @spec list_models() :: {:ok, [model_info()]} | {:error, String.t()}
  def list_models do
    @fuse_name
    |> CircuitBreaker.with_fuse(fn -> do_list_models() end, @fuse_opts)
    |> handle_circuit_error("Ollama")
  end

  defp do_list_models do
    case Req.get("#{base_url()}/api/tags", receive_timeout: timeout(), retry: false) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        {:ok, ResponseFormatter.format_model_list(models, @provider_prefix)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama models request failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to load models. Please check if Ollama is running."}

      {:error, exception} ->
        Logger.warning("Ollama models request error: #{Exception.message(exception)}")
        {:error, "Failed to connect to Ollama. Please check if it is running."}
    end
  end

  @doc """
  Sends a non-streaming chat completion request.
  """
  @impl Chatbot.OllamaBehaviour
  @spec chat_completion(messages(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_completion(messages, model) do
    result =
      CircuitBreaker.with_fuse(
        @fuse_name,
        fn -> do_chat_completion(messages, model) end,
        @fuse_opts
      )

    handle_circuit_error(result, "Ollama")
  end

  defp do_chat_completion(messages, model) do
    model_name = strip_provider_prefix(model)
    body = %{model: model_name, messages: messages, stream: false}

    case Req.post("#{base_url()}/api/chat", json: body, receive_timeout: timeout(), retry: false) do
      {:ok, %{status: 200, body: %{"message" => message} = response}} ->
        {:ok, ResponseFormatter.format_chat_response(message, response, model_name)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama chat completion failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to get AI response. Please try again."}

      {:error, exception} ->
        Logger.warning("Ollama chat completion error: #{Exception.message(exception)}")
        {:error, "Failed to connect to Ollama. Please check if it is running."}
    end
  end

  @doc """
  Sends a non-streaming chat completion request with tool definitions.
  """
  @impl Chatbot.OllamaBehaviour
  @spec chat_with_tools(messages(), [map()], String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_with_tools(messages, tools, model) do
    result =
      CircuitBreaker.with_fuse(
        @fuse_name,
        fn -> do_chat_with_tools(messages, tools, model) end,
        @fuse_opts
      )

    handle_circuit_error(result, "Ollama")
  end

  defp do_chat_with_tools(messages, tools, model) do
    model_name = strip_provider_prefix(model)
    ollama_tools = ResponseFormatter.convert_tools_to_ollama(tools)
    body = %{model: model_name, messages: messages, tools: ollama_tools, stream: false}

    case Req.post("#{base_url()}/api/chat", json: body, receive_timeout: timeout(), retry: false) do
      {:ok, %{status: 200, body: %{"message" => message} = response}} ->
        {:ok, ResponseFormatter.format_tool_response(message, response, model_name)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Ollama chat with tools failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to get AI response. Please try again."}

      {:error, exception} ->
        Logger.warning("Ollama chat with tools error: #{Exception.message(exception)}")
        {:error, "Failed to connect to Ollama. Please check if it is running."}
    end
  end

  @doc """
  Sends a chat completion request with streaming enabled.
  """
  @impl Chatbot.OllamaBehaviour
  @spec stream_chat_completion(messages(), String.t(), pid()) :: :ok | {:error, String.t()}
  def stream_chat_completion(messages, model, pid) do
    case CircuitBreaker.ensure_installed(@fuse_name, @fuse_opts) do
      :blown ->
        error_msg = "Ollama service is temporarily unavailable. Please try again later."
        send(pid, {:error, error_msg})
        {:error, error_msg}

      :ok ->
        do_stream_chat_completion(messages, model, pid)
    end
  end

  defp do_stream_chat_completion(messages, model, pid) do
    model_name = strip_provider_prefix(model)
    body = %{model: model_name, messages: messages, stream: true}
    finch_stream = Streaming.create_stream_handler(pid)

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
        CircuitBreaker.melt(@fuse_name)
        Logger.warning("Ollama streaming error: #{Exception.message(e)}")
        error_msg = "Failed to get AI response. Please try again."
        send(pid, {:error, error_msg})
        {:error, error_msg}
    end
  end

  # Converts circuit breaker errors to user-friendly messages
  defp handle_circuit_error({:error, :circuit_open}, provider) do
    {:error, "#{provider} service is temporarily unavailable. Please try again later."}
  end

  defp handle_circuit_error(result, _provider), do: result
end
