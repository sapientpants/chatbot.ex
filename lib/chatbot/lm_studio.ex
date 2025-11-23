defmodule Chatbot.LMStudio do
  @moduledoc """
  Client for interacting with LM Studio's OpenAI-compatible API.
  """

  @base_url Application.compile_env(:chatbot, :lm_studio_url, "http://localhost:1234/v1")

  @doc """
  Fetches the list of available models from LM Studio.

  ## Examples

      iex> list_models()
      {:ok, [%{"id" => "model-name", ...}]}

      iex> list_models()
      {:error, "Connection refused"}

  """
  def list_models do
    case Req.get("#{@base_url}/models") do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        {:ok, models}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  @doc """
  Sends a chat completion request with streaming enabled.

  ## Parameters
    - messages: List of messages in OpenAI format [%{role: "user", content: "..."}]
    - model: Model name to use
    - pid: Process ID to send streaming chunks to

  ## Examples

      iex> stream_chat_completion([%{role: "user", content: "Hello"}], "model-name", self())
      :ok

  """
  def stream_chat_completion(messages, model, pid) do
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
      Req.post!("#{@base_url}/chat/completions",
        json: body,
        receive_timeout: 300_000,
        finch_request: finch_stream
      )

      :ok
    rescue
      e ->
        send(pid, {:error, Exception.message(e)})
        {:error, Exception.message(e)}
    end
  end

  defp process_sse_chunk("", _pid), do: :ok
  defp process_sse_chunk("[DONE]", _pid), do: :ok

  defp process_sse_chunk(json_string, pid) do
    case Jason.decode(json_string) do
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
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

  ## Parameters
    - messages: List of messages in OpenAI format
    - model: Model name to use

  ## Examples

      iex> chat_completion([%{role: "user", content: "Hello"}], "model-name")
      {:ok, %{"choices" => [%{"message" => %{"content" => "Hi there!"}}]}}

  """
  def chat_completion(messages, model) do
    body = %{
      model: model,
      messages: messages,
      temperature: 0.7
    }

    case Req.post("#{@base_url}/chat/completions", json: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, "Status #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end
end
