defmodule Chatbot.MCP.ToolExecutor do
  @moduledoc """
  Executes MCP tool calls with isolation, timeout, and error handling.

  - Uses Task.Supervisor.async_nolink for process isolation
  - Configurable timeout per tool execution
  - Truncates large results to prevent context overflow
  - Reports telemetry for observability
  """

  alias Chatbot.MCP.ClientRegistry
  alias Chatbot.MCP.ToolRegistry

  require Logger

  @default_timeout 30_000
  @max_result_size 100_000

  @type tool_call :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:arguments) => map()
        }

  @type tool_result :: %{
          tool_call_id: String.t(),
          tool_name: String.t(),
          result: map() | nil,
          error: String.t() | nil,
          duration_ms: integer()
        }

  @doc """
  Executes a single tool call and returns the result.
  """
  @spec execute(tool_call(), binary(), keyword()) :: tool_result()
  def execute(tool_call, user_id, opts \\ [])

  def execute(%{"id" => id, "name" => name, "arguments" => args} = _tool_call, user_id, opts) do
    timeout = opts[:timeout] || config(:tool_timeout_ms) || @default_timeout
    start_time = System.monotonic_time(:millisecond)

    result =
      case ToolRegistry.resolve_tool(name, user_id) do
        {:ok, _client, server} ->
          execute_with_timeout(name, args, server, timeout)

        {:error, :tool_not_found} ->
          {:error, "Tool '#{name}' not found or not enabled"}

        {:error, :circuit_open} ->
          {:error, "Tool server temporarily unavailable"}

        {:error, reason} ->
          {:error, "Failed to resolve tool: #{inspect(reason)}"}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    build_result(id, name, result, duration_ms)
  end

  # Handle string keys
  def execute(%{id: id, name: name, arguments: args}, user_id, opts) do
    execute(%{"id" => id, "name" => name, "arguments" => args}, user_id, opts)
  end

  @doc """
  Executes multiple tool calls in parallel and returns all results.
  """
  @spec execute_all([tool_call()], binary(), keyword()) :: [tool_result()]
  def execute_all(tool_calls, user_id, opts \\ []) do
    timeout = opts[:timeout] || config(:tool_timeout_ms) || @default_timeout

    # Start all tasks in parallel, keeping reference to original tool_call
    tasks_with_calls =
      Enum.map(tool_calls, fn tool_call ->
        task =
          Task.Supervisor.async_nolink(Chatbot.TaskSupervisor, fn ->
            execute(tool_call, user_id, opts)
          end)

        {task, tool_call}
      end)

    # Collect results, using original tool_call info on timeout
    Enum.map(tasks_with_calls, fn {task, tool_call} ->
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} ->
          result

        nil ->
          # Task timed out - use original tool_call info for error reporting
          tool_id = tool_call["id"] || tool_call[:id] || "unknown"
          tool_name = tool_call["name"] || tool_call[:name] || "unknown"

          %{
            tool_call_id: tool_id,
            tool_name: tool_name,
            result: nil,
            error: "Tool execution timed out",
            duration_ms: timeout
          }
      end
    end)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp execute_with_timeout(name, args, server, timeout) do
    task =
      Task.Supervisor.async_nolink(Chatbot.TaskSupervisor, fn ->
        do_execute(name, args, server)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        Logger.warning("Tool #{name} timed out after #{timeout}ms")
        {:error, "Tool execution timed out after #{timeout}ms"}
    end
  end

  defp do_execute(name, args, server) do
    client_module = get_client_module(server.id)

    try do
      case client_module.call_tool(name, args) do
        {:ok, %{is_error: false, result: result}} ->
          ClientRegistry.record_success(server.id)
          {:ok, truncate_result(result)}

        {:ok, %{is_error: true, result: error}} ->
          ClientRegistry.record_failure(server.id)
          {:error, format_error(error)}

        {:ok, %{"content" => content}} ->
          ClientRegistry.record_success(server.id)
          {:ok, truncate_result(content)}

        {:ok, result} when is_map(result) ->
          ClientRegistry.record_success(server.id)
          {:ok, truncate_result(result)}

        {:error, reason} ->
          ClientRegistry.record_failure(server.id)
          {:error, format_error(reason)}

        other ->
          Logger.warning("Unexpected tool result: #{inspect(other)}")
          {:ok, truncate_result(other)}
      end
    rescue
      e ->
        Logger.error("Tool execution error: #{inspect(e)}")
        ClientRegistry.record_failure(server.id)
        {:error, "Internal error: #{Exception.message(e)}"}
    end
  end

  # Use shared function from ClientRegistry for consistent module naming
  # See ClientRegistry.client_module_name/1 for security documentation
  defp get_client_module(server_id) do
    ClientRegistry.client_module_name(server_id)
  end

  defp build_result(id, name, {:ok, result}, duration_ms) do
    %{
      tool_call_id: id,
      tool_name: name,
      result: result,
      error: nil,
      duration_ms: duration_ms
    }
  end

  defp build_result(id, name, {:error, error}, duration_ms) do
    %{
      tool_call_id: id,
      tool_name: name,
      result: nil,
      error: error,
      duration_ms: duration_ms
    }
  end

  defp truncate_result(result) when is_binary(result) do
    max_size = config(:max_result_size_bytes) || @max_result_size

    if byte_size(result) > max_size do
      String.slice(result, 0, max_size) <> "\n... [truncated]"
    else
      result
    end
  end

  defp truncate_result(result) when is_map(result) or is_list(result) do
    encoded = Jason.encode!(result)
    max_size = config(:max_result_size_bytes) || @max_result_size

    if byte_size(encoded) > max_size do
      # Return truncated JSON string
      String.slice(encoded, 0, max_size) <> "... [truncated]"
    else
      result
    end
  end

  defp truncate_result(result), do: result

  defp format_error(error) when is_binary(error), do: error
  defp format_error(%{"message" => message}), do: message
  defp format_error(error), do: inspect(error)

  defp config(key) do
    Application.get_env(:chatbot, :mcp, [])[key]
  end
end
