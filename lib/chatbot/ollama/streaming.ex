defmodule Chatbot.Ollama.Streaming do
  @moduledoc """
  Handles NDJSON streaming for Ollama API responses.

  Ollama uses NDJSON (newline-delimited JSON) for streaming responses,
  not SSE (Server-Sent Events) like some other providers.

  Format:
      {"message": {"content": "token"}, "done": false}
      {"message": {"content": ""}, "done": true}

  """

  require Logger

  @doc """
  Creates a Finch streaming handler for NDJSON responses.

  The handler processes incoming data chunks, parses complete JSON lines,
  and sends content chunks to the specified process.

  ## Parameters

  - `pid` - Process ID to send streaming chunks to

  ## Messages sent to pid

  - `{:chunk, content}` - A token chunk
  - `{:done, ""}` - Streaming complete (sent by caller, not this handler)
  - `{:error, reason}` - An error occurred

  ## Returns

  A function suitable for use with `Req.post!/2`'s `:finch_request` option.

  """
  @spec create_stream_handler(pid()) :: (any(), any(), any(), any() -> {any(), any()})
  def create_stream_handler(pid) do
    fn request, finch_request, finch_name, finch_options ->
      buffer = ""

      stream_handler = fn
        {:status, status}, {response, buf} ->
          {%{response | status: status}, buf}

        {:headers, headers}, {response, buf} ->
          {%{response | headers: headers}, buf}

        {:data, data}, {response, buf} ->
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

        {:error, exception, _accumulator} ->
          Logger.warning("Finch stream error: #{inspect(exception)}")
          send(pid, {:error, "Failed to get AI response. Please try again."})
          raise "Finch streaming failed: #{inspect(exception)}"
      end
    end
  end

  @doc """
  Processes NDJSON data, handling incomplete lines.

  Returns the remaining buffer (incomplete line) and a status atom.

  ## Parameters

  - `data` - The raw data to process (may contain multiple lines)
  - `pid` - Process ID to send parsed content chunks to

  ## Returns

  `{remaining_buffer, :ok}`

  """
  @spec process_ndjson_data(String.t(), pid()) :: {String.t(), :ok}
  def process_ndjson_data(data, pid) do
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

  @doc """
  Processes a single NDJSON line.

  Parses the JSON and sends content chunks to the process if present.

  ## Parameters

  - `json_string` - A single JSON line to parse
  - `pid` - Process ID to send content to

  """
  @spec process_ndjson_line(String.t(), pid()) :: :ok
  def process_ndjson_line("", _pid), do: :ok

  def process_ndjson_line(json_string, pid) do
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
