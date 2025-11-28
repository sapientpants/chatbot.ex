defmodule Chatbot.LMStudio do
  @moduledoc """
  Client for interacting with LM Studio's OpenAI-compatible API.

  Configuration is loaded from application config under `:chatbot, :lm_studio`.
  Includes circuit breaker protection using Fuse to prevent cascading failures.
  """

  @behaviour Chatbot.LMStudioBehaviour

  require Logger

  @typedoc "A chat message in OpenAI format"
  @type message :: %{role: String.t(), content: String.t()}

  @typedoc "A list of chat messages"
  @type messages :: [message()]

  @typedoc "Model information from LM Studio"
  @type model_info :: %{String.t() => any()}

  @fuse_name :lm_studio_fuse
  @fuse_options {{:standard, 5, 60_000}, {:reset, 30_000}}

  defp base_url do
    config()[:base_url] || "http://localhost:1234/v1"
  end

  defp stream_timeout do
    config()[:stream_timeout_ms] || 300_000
  end

  defp config do
    Application.get_env(:chatbot, :lm_studio, [])
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
        {:error, "LM Studio service is temporarily unavailable. Please try again later."}

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
  Fetches the list of available models from LM Studio.
  Protected by circuit breaker to prevent cascading failures.

  ## Examples

      iex> list_models()
      {:ok, [%{"id" => "model-name", ...}]}

      iex> list_models()
      {:error, "Connection refused"}

  """
  @spec list_models() :: {:ok, [model_info()]} | {:error, String.t()}
  def list_models do
    with_circuit_breaker(fn ->
      case Req.get("#{base_url()}/models", retry: false) do
        {:ok, %{status: 200, body: %{"data" => models}}} ->
          {:ok, models}

        {:ok, %{status: status}} ->
          Logger.warning("LM Studio models request failed with status #{status}")
          {:error, "Failed to load models. Please check if LM Studio is running."}

        {:error, exception} ->
          Logger.warning("LM Studio models request error: #{Exception.message(exception)}")
          {:error, "Failed to connect to LM Studio. Please check if it is running."}
      end
    end)
  end

  @doc """
  Sends a chat completion request with streaming enabled.
  Protected by circuit breaker to prevent cascading failures.

  ## Parameters
    - messages: List of messages in OpenAI format [%{role: "user", content: "..."}]
    - model: Model name to use
    - pid: Process ID to send streaming chunks to

  ## Examples

      iex> stream_chat_completion([%{role: "user", content: "Hello"}], "model-name", self())
      :ok

  """
  @spec stream_chat_completion(messages(), String.t(), pid()) :: :ok | {:error, String.t()}
  def stream_chat_completion(messages, model, pid) do
    # Check circuit breaker first
    case ensure_fuse_installed() do
      :blown ->
        error_msg = "LM Studio service is temporarily unavailable. Please try again later."
        send(pid, {:error, error_msg})
        {:error, error_msg}

      :ok ->
        do_stream_chat_completion(messages, model, pid)
    end
  end

  defp do_stream_chat_completion(messages, model, pid) do
    body = %{
      model: model,
      messages: messages,
      stream: true,
      temperature: 0.7
    }

    # Custom Finch streaming function to handle SSE
    finch_stream = fn request, finch_request, finch_name, finch_options ->
      stream_handler = fn
        {:status, status}, response ->
          %{response | status: status}

        {:headers, headers}, response ->
          %{response | headers: headers}

        {:data, data}, response ->
          # Parse SSE format: "data: <JSON>\n\n"
          data
          |> String.split("data: ")
          |> Enum.each(fn chunk ->
            chunk = String.trim(chunk)
            process_sse_chunk(chunk, pid)
          end)

          response
      end

      {:ok, response} =
        Finch.stream(
          finch_request,
          finch_name,
          Req.Response.new(),
          stream_handler,
          finch_options
        )

      send(pid, {:done, ""})
      {request, response}
    end

    try do
      Req.post!("#{base_url()}/chat/completions",
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
        Logger.warning("LM Studio streaming error: #{Exception.message(e)}")
        error_msg = "Failed to get AI response. Please try again."
        send(pid, {:error, error_msg})
        {:error, error_msg}
    end
  end

  defp process_sse_chunk("", _pid), do: :ok
  defp process_sse_chunk("[DONE]", _pid), do: :ok

  defp process_sse_chunk(json_string, pid) do
    case Jason.decode(json_string) do
      {:ok, %{"choices" => [%{"delta" => delta} | _rest]}} ->
        if content = delta["content"] do
          send(pid, {:chunk, content})
        end

      {:ok, _other} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @doc """
  Sends a non-streaming chat completion request.
  Protected by circuit breaker to prevent cascading failures.

  ## Parameters
    - messages: List of messages in OpenAI format
    - model: Model name to use

  ## Examples

      iex> chat_completion([%{role: "user", content: "Hello"}], "model-name")
      {:ok, %{"choices" => [%{"message" => %{"content" => "Hi there!"}}]}}

  """
  @spec chat_completion(messages(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def chat_completion(messages, model) do
    with_circuit_breaker(fn ->
      body = %{
        model: model,
        messages: messages,
        temperature: 0.7
      }

      case Req.post("#{base_url()}/chat/completions", json: body, retry: false) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          Logger.warning(
            "LM Studio chat completion failed: status=#{status}, body=#{inspect(body)}"
          )

          {:error, "Failed to get AI response. Please try again."}

        {:error, exception} ->
          Logger.warning("LM Studio chat completion error: #{Exception.message(exception)}")
          {:error, "Failed to connect to LM Studio. Please check if it is running."}
      end
    end)
  end
end
