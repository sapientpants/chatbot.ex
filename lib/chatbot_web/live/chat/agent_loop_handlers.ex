defmodule ChatbotWeb.Live.Chat.AgentLoopHandlers do
  @moduledoc """
  Handles agent loop events for chat LiveViews.

  Provides event handlers for tool calling and agent loop completion,
  including progress tracking for pending tool calls and result handling.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Chatbot.Chat
  alias ChatbotWeb.Live.Chat.MessageHelpers
  alias ChatbotWeb.Live.Chat.TaskRegistry

  @doc """
  Handles a tool call starting during agent loop execution.
  """
  @spec handle_tool_call_start(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_tool_call_start(tool_call, socket) do
    pending = [tool_call | socket.assigns[:pending_tool_calls] || []]
    {:noreply, assign(socket, :pending_tool_calls, pending)}
  end

  @doc """
  Handles a tool call completing during agent loop execution.
  """
  @spec handle_tool_call_complete(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_tool_call_complete(result, socket) do
    results = [result | socket.assigns[:tool_results] || []]

    pending =
      Enum.reject(socket.assigns[:pending_tool_calls] || [], fn call ->
        (call["id"] || call[:id]) == result.tool_call_id
      end)

    {:noreply,
     socket
     |> assign(:tool_results, results)
     |> assign(:pending_tool_calls, pending)}
  end

  @doc """
  Handles the agent loop completing (success or failure).
  """
  @spec handle_agent_complete(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_agent_complete(result, socket) do
    maybe_unregister_streaming_task(socket)

    if result.success do
      handle_agent_success(result, socket)
    else
      handle_agent_error(result, socket)
    end
  end

  # Handles successful agent loop completion
  defp handle_agent_success(result, socket) do
    conversation_id = socket.assigns.current_conversation.id
    complete_message = result.content || ""

    message_attrs = %{
      conversation_id: conversation_id,
      role: "assistant",
      content: complete_message
    }

    case Chat.create_message(message_attrs) do
      {:ok, message} ->
        current_conv = socket.assigns.current_conversation
        updated_conv = %{current_conv | updated_at: DateTime.utc_now()}

        conversations =
          MessageHelpers.update_conversation_in_list(socket.assigns.conversations, updated_conv)

        MessageHelpers.maybe_extract_facts(socket, complete_message, message.id)

        {:noreply,
         socket
         |> stream_insert(:messages, message, at: -1)
         |> assign(:current_conversation, updated_conv)
         |> assign(:conversations, conversations)
         |> reset_agent_state()
         |> assign(:last_user_message, nil)
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save assistant message")
         |> reset_agent_state()}
    end
  end

  # Handles agent loop error
  defp handle_agent_error(result, socket) do
    error_msg = result.error || "Agent loop failed"

    {:noreply,
     socket
     |> put_flash(:error, "Error: #{error_msg}")
     |> reset_agent_state()}
  end

  defp reset_agent_state(socket) do
    socket
    |> assign(:is_streaming, false)
    |> assign(:agent_mode, false)
    |> assign(:pending_tool_calls, [])
    |> assign(:tool_results, [])
  end

  # Unregisters a streaming task if one is active
  defp maybe_unregister_streaming_task(socket) do
    user_id = socket.assigns.current_user.id
    task_pid = socket.assigns[:streaming_task_pid]

    if task_pid do
      TaskRegistry.unregister_task(user_id, task_pid)
    end
  end
end
