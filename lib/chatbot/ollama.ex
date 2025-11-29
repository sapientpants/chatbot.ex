defmodule Chatbot.Ollama do
  @moduledoc """
  Client for interacting with Ollama's embedding API.

  Configuration is loaded from application config under `:chatbot, :ollama`.
  Includes circuit breaker protection using Fuse to prevent cascading failures.

  ## Configuration

      config :chatbot, :ollama,
        base_url: "http://localhost:11434",
        embedding_model: "qwen3-embedding:0.6b",
        embedding_dimension: 1024,
        timeout_ms: 30_000

  """

  @behaviour Chatbot.OllamaBehaviour

  require Logger

  @fuse_name :ollama_fuse
  @fuse_options {{:standard, 5, 60_000}, {:reset, 30_000}}

  defp base_url do
    config()[:base_url] || "http://localhost:11434"
  end

  defp embedding_model do
    config()[:embedding_model] || "qwen3-embedding:0.6b"
  end

  defp timeout do
    config()[:timeout_ms] || 30_000
  end

  defp config do
    Application.get_env(:chatbot, :ollama, [])
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
end
