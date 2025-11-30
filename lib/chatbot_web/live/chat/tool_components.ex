defmodule ChatbotWeb.Live.Chat.ToolComponents do
  @moduledoc """
  LiveView components for rendering tool calls and results inline in chat messages.

  Provides collapsible blocks showing:
  - Tool name with status indicator
  - Execution duration
  - Expandable arguments (JSON)
  - Expandable result or error
  """

  use Phoenix.Component

  @doc """
  Renders a list of tool calls from an assistant message.
  """
  attr :tool_calls, :list, required: true
  attr :tool_results, :list, default: []

  @spec tool_calls_list(map()) :: Phoenix.LiveView.Rendered.t()
  def tool_calls_list(assigns) do
    ~H"""
    <div class="mt-2 space-y-2">
      <div :for={call <- @tool_calls} class="tool-call">
        <.tool_call_block
          call={call}
          result={find_result(@tool_results, call["id"] || call[:id])}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a single tool call with its result.
  """
  attr :call, :map, required: true
  attr :result, :map, default: nil

  @spec tool_call_block(map()) :: Phoenix.LiveView.Rendered.t()
  def tool_call_block(assigns) do
    ~H"""
    <details class="group border border-zinc-700 rounded-lg overflow-hidden bg-zinc-800/50">
      <summary class="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-zinc-700/50 transition-colors">
        <.status_icon status={get_status(@result)} />
        <span class="font-mono text-sm text-zinc-300">
          {get_tool_name(@call)}
        </span>
        <span :if={@result && @result.duration_ms} class="ml-auto text-xs text-zinc-500">
          {format_duration(@result.duration_ms)}
        </span>
        <svg
          class="w-4 h-4 text-zinc-500 transition-transform group-open:rotate-180"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </summary>

      <div class="px-3 py-2 border-t border-zinc-700 space-y-2">
        <div>
          <div class="text-xs text-zinc-500 mb-1">Arguments:</div>
          <pre class="text-xs font-mono bg-zinc-900 p-2 rounded overflow-x-auto max-h-32 overflow-y-auto"><code>{format_arguments(@call)}</code></pre>
        </div>

        <div :if={@result}>
          <div class="text-xs text-zinc-500 mb-1">
            {if @result.error, do: "Error:", else: "Result:"}
          </div>
          <pre class={[
            "text-xs font-mono p-2 rounded overflow-x-auto max-h-48 overflow-y-auto",
            if(@result.error, do: "bg-red-900/30 text-red-300", else: "bg-zinc-900")
          ]}><code>{format_result(@result)}</code></pre>
        </div>

        <div :if={!@result} class="text-xs text-zinc-500 italic">
          Executing...
        </div>
      </div>
    </details>
    """
  end

  @doc """
  Renders a status icon for the tool call state.
  """
  attr :status, :atom, required: true

  @spec status_icon(map()) :: Phoenix.LiveView.Rendered.t()
  def status_icon(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center justify-center w-5 h-5 rounded-full text-xs",
      status_class(@status)
    ]}>
      {status_icon_content(@status)}
    </span>
    """
  end

  @doc """
  Renders a tool execution progress indicator for the chat UI.
  """
  attr :pending_tools, :list, default: []
  attr :executing_tools, :list, default: []

  @spec tool_progress(map()) :: Phoenix.LiveView.Rendered.t()
  def tool_progress(assigns) do
    ~H"""
    <div
      :if={length(@pending_tools) > 0 || length(@executing_tools) > 0}
      class="flex items-center gap-2 text-sm text-zinc-400 py-2"
    >
      <div class="animate-spin h-4 w-4 border-2 border-zinc-500 border-t-blue-400 rounded-full" />
      <span :if={length(@executing_tools) > 0}>
        Executing {Enum.join(Enum.map(@executing_tools, &get_tool_name/1), ", ")}...
      </span>
      <span :if={length(@executing_tools) == 0 && length(@pending_tools) > 0}>
        Preparing tools...
      </span>
    </div>
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp find_result(results, call_id) when is_list(results) do
    Enum.find(results, fn r ->
      r.tool_call_id == call_id || r[:tool_call_id] == call_id
    end)
  end

  defp find_result(_results, _call_id), do: nil

  defp get_tool_name(%{"function" => %{"name" => name}}), do: name
  defp get_tool_name(%{function: %{name: name}}), do: name
  defp get_tool_name(%{"name" => name}), do: name
  defp get_tool_name(%{name: name}), do: name
  defp get_tool_name(_call), do: "unknown"

  defp get_status(nil), do: :pending
  defp get_status(%{error: error}) when error != nil, do: :error
  defp get_status(%{result: _result}), do: :success
  defp get_status(_other), do: :pending

  defp status_class(:pending), do: "bg-zinc-600 text-zinc-300"
  defp status_class(:running), do: "bg-blue-600 text-blue-100 animate-pulse"
  defp status_class(:success), do: "bg-green-600 text-green-100"
  defp status_class(:error), do: "bg-red-600 text-red-100"

  defp status_icon_content(:pending), do: "..."
  defp status_icon_content(:running), do: "~"
  defp status_icon_content(:success), do: "+"
  defp status_icon_content(:error), do: "!"

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_arguments(%{"function" => %{"arguments" => args}}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _error -> args
    end
  end

  defp format_arguments(%{"function" => %{"arguments" => args}}) when is_map(args) do
    Jason.encode!(args, pretty: true)
  end

  defp format_arguments(%{function: %{arguments: args}}) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _error -> args
    end
  end

  defp format_arguments(%{function: %{arguments: args}}) when is_map(args) do
    Jason.encode!(args, pretty: true)
  end

  defp format_arguments(%{"arguments" => args}) when is_map(args) do
    Jason.encode!(args, pretty: true)
  end

  defp format_arguments(%{arguments: args}) when is_map(args) do
    Jason.encode!(args, pretty: true)
  end

  defp format_arguments(_other), do: "{}"

  defp format_result(%{error: error}) when error != nil, do: error

  defp format_result(%{result: result}) when is_binary(result), do: result

  defp format_result(%{result: result}) when is_map(result) or is_list(result) do
    Jason.encode!(result, pretty: true)
  end

  defp format_result(%{result: result}), do: inspect(result)
  defp format_result(_other), do: ""
end
