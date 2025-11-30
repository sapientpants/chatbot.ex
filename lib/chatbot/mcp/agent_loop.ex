defmodule Chatbot.MCP.AgentLoop do
  @moduledoc """
  Implements the observe-think-act cycle for tool-enabled conversations.

  The agent loop:
  1. Sends messages with available tools to the LLM (non-streaming)
  2. If the LLM returns tool_calls, executes them via ToolExecutor
  3. Appends tool results to messages and loops
  4. Terminates when LLM returns content without tool_calls, or limits are reached

  Termination conditions:
  - LLM returns content without tool_calls (success)
  - Max iterations reached (default 10)
  - Total timeout exceeded (default 2 minutes)
  - All MCP servers unavailable (circuit breakers open)
  """

  alias Chatbot.MCP.ToolExecutor
  alias Chatbot.MCP.ToolRegistry

  require Logger

  @default_max_iterations 10
  @default_timeout_ms 120_000

  @type loop_state :: %{
          messages: [map()],
          user_id: binary(),
          model: String.t(),
          tools: [map()],
          iteration: integer(),
          start_time: integer(),
          on_tool_call: (map() -> :ok) | nil,
          on_tool_result: (map() -> :ok) | nil
        }

  @type loop_result :: %{
          success: boolean(),
          content: String.t() | nil,
          messages: [map()],
          tool_calls_made: integer(),
          iterations: integer(),
          error: String.t() | nil
        }

  @doc """
  Runs the agent loop with the given messages and options.

  Options:
  - `:model` - The model to use (required)
  - `:user_id` - The user ID for tool resolution (required)
  - `:max_iterations` - Maximum loop iterations (default 10)
  - `:timeout_ms` - Total timeout in milliseconds (default 120000)
  - `:on_tool_call` - Callback when a tool call starts: fn tool_call -> :ok
  - `:on_tool_result` - Callback when a tool call completes: fn result -> :ok
  """
  @spec run([map()], keyword()) :: loop_result()
  def run(messages, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    model = Keyword.fetch!(opts, :model)

    # Get available tools for this user
    case ToolRegistry.get_tools_for_user(user_id) do
      {:ok, []} ->
        # No tools available, just do a regular completion
        run_without_tools(messages, model)

      {:ok, tools} ->
        state = %{
          messages: messages,
          user_id: user_id,
          model: model,
          tools: tools,
          iteration: 0,
          start_time: System.monotonic_time(:millisecond),
          tool_calls_made: 0,
          on_tool_call: opts[:on_tool_call],
          on_tool_result: opts[:on_tool_result],
          max_iterations:
            opts[:max_iterations] || config(:max_agent_iterations) ||
              @default_max_iterations,
          timeout_ms: opts[:timeout_ms] || config(:agent_loop_timeout_ms) || @default_timeout_ms
        }

        loop(state)
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp loop(state) do
    cond do
      state.iteration >= state.max_iterations ->
        Logger.warning("Agent loop reached max iterations (#{state.max_iterations})")
        terminate(state, :max_iterations)

      timeout_exceeded?(state) ->
        Logger.warning("Agent loop timeout exceeded")
        terminate(state, :timeout)

      true ->
        case call_llm(state) do
          {:ok, response} ->
            handle_response(response, state)

          {:error, reason} ->
            Logger.error("LLM call failed: #{inspect(reason)}")
            terminate(state, {:llm_error, reason})
        end
    end
  end

  defp call_llm(state) do
    # Use ProviderRouter to call with tools (non-streaming)
    Chatbot.ProviderRouter.chat_completion_with_tools(
      state.messages,
      state.tools,
      model: state.model
    )
  end

  defp handle_response(response, state) do
    tool_calls = extract_tool_calls(response)
    content = extract_content(response)

    cond do
      # No tool calls - we're done
      Enum.empty?(tool_calls) and content ->
        # credo:disable-for-lines:5 Credo.Check.Refactor.AppendSingleItem
        %{
          success: true,
          content: content,
          messages: state.messages ++ [build_assistant_message(content, [])],
          tool_calls_made: state.tool_calls_made,
          iterations: state.iteration + 1,
          error: nil
        }

      # Has tool calls - execute them and continue
      not Enum.empty?(tool_calls) ->
        # Notify about tool calls starting
        if state.on_tool_call do
          Enum.each(tool_calls, state.on_tool_call)
        end

        # Execute all tool calls
        results = ToolExecutor.execute_all(tool_calls, state.user_id)

        # Notify about tool results
        if state.on_tool_result do
          Enum.each(results, state.on_tool_result)
        end

        # Build new messages with assistant response and tool results
        assistant_msg = build_assistant_message(content, tool_calls)
        tool_messages = Enum.map(results, &build_tool_message/1)

        # credo:disable-for-lines:4 Credo.Check.Refactor.AppendSingleItem
        new_state = %{
          state
          | messages: state.messages ++ [assistant_msg | tool_messages],
            iteration: state.iteration + 1,
            tool_calls_made: state.tool_calls_made + length(tool_calls)
        }

        loop(new_state)

      # No content and no tool calls - unexpected
      true ->
        Logger.warning("LLM returned neither content nor tool calls")
        terminate(state, :empty_response)
    end
  end

  defp extract_tool_calls(%{"message" => %{"tool_calls" => calls}}) when is_list(calls), do: calls
  defp extract_tool_calls(%{tool_calls: calls}) when is_list(calls), do: calls
  defp extract_tool_calls(_response), do: []

  defp extract_content(%{"message" => %{"content" => content}}), do: content
  defp extract_content(%{content: content}), do: content
  defp extract_content(_response), do: nil

  defp build_assistant_message(content, tool_calls) do
    msg = %{
      "role" => "assistant",
      "content" => content || ""
    }

    if Enum.empty?(tool_calls) do
      msg
    else
      Map.put(msg, "tool_calls", format_tool_calls(tool_calls))
    end
  end

  defp format_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn call ->
      %{
        "id" => call["id"] || call[:id],
        "type" => "function",
        "function" => %{
          "name" => get_in(call, ["function", "name"]) || call["name"],
          "arguments" =>
            get_in(call, ["function", "arguments"]) || Jason.encode!(call["arguments"])
        }
      }
    end)
  end

  defp build_tool_message(result) do
    content =
      cond do
        result.error -> "Error: #{result.error}"
        is_binary(result.result) -> result.result
        true -> Jason.encode!(result.result)
      end

    %{
      "role" => "tool",
      "tool_call_id" => result.tool_call_id,
      "name" => result.tool_name,
      "content" => content
    }
  end

  defp terminate(state, reason) do
    error_msg =
      case reason do
        :max_iterations -> "Maximum iterations (#{state.max_iterations}) reached"
        :timeout -> "Total timeout exceeded"
        :empty_response -> "LLM returned empty response"
        {:llm_error, err} -> "LLM error: #{inspect(err)}"
        other -> "Unknown error: #{inspect(other)}"
      end

    %{
      success: false,
      content: nil,
      messages: state.messages,
      tool_calls_made: state.tool_calls_made,
      iterations: state.iteration,
      error: error_msg
    }
  end

  defp timeout_exceeded?(state) do
    elapsed = System.monotonic_time(:millisecond) - state.start_time
    elapsed >= state.timeout_ms
  end

  defp run_without_tools(messages, model) do
    case Chatbot.ProviderRouter.chat_completion(messages, model: model) do
      {:ok, response} ->
        content = extract_content(response)

        # credo:disable-for-lines:5 Credo.Check.Refactor.AppendSingleItem
        %{
          success: true,
          content: content,
          messages: messages ++ [build_assistant_message(content, [])],
          tool_calls_made: 0,
          iterations: 1,
          error: nil
        }

      {:error, reason} ->
        %{
          success: false,
          content: nil,
          messages: messages,
          tool_calls_made: 0,
          iterations: 0,
          error: "LLM error: #{inspect(reason)}"
        }
    end
  end

  defp config(key) do
    Application.get_env(:chatbot, :mcp, [])[key]
  end
end
