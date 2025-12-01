defmodule ChatbotWeb.Live.Chat.MessageProcessor do
  @moduledoc """
  Handles message processing and AI response streaming for chat.

  This module manages:
  - Creating user messages
  - Starting streaming tasks
  - Running agent loops
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Chatbot.Chat
  alias Chatbot.MCP.AgentLoop
  alias Chatbot.MCP.ToolRegistry
  alias Chatbot.Memory.ContextBuilder
  alias Chatbot.ProviderRouter
  alias ChatbotWeb.Live.Chat.MessageHelpers
  alias ChatbotWeb.Live.Chat.TaskRegistry

  require Logger

  @doc """
  Processes a user message and starts AI response generation.
  """
  @spec process(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def process(content, socket) do
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id

    case Chat.create_message(%{conversation_id: conversation_id, role: "user", content: content}) do
      {:ok, user_message} ->
        socket = maybe_update_title(socket, content)
        model = socket.assigns.selected_model || "default"

        {:ok, openai_messages} =
          ContextBuilder.build_context(conversation_id, user_id, current_query: content)

        socket = maybe_update_model(socket, model)

        if ToolRegistry.user_has_tools?(user_id) do
          start_agent_loop(socket, user_message, openai_messages, model, user_id)
        else
          start_streaming(socket, user_message, openai_messages, model, user_id)
        end

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save message")}
    end
  end

  @doc """
  Saves the completed assistant message to the database.
  """
  @spec save_assistant_message(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def save_assistant_message(socket, conversation_id, complete_message) do
    MessageHelpers.save_assistant_message(
      socket,
      conversation_id,
      complete_message,
      &reset_streaming_state/1
    )
  end

  # Private functions

  defp start_streaming(socket, user_message, openai_messages, model, user_id) do
    liveview_pid = self()

    case Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
           ProviderRouter.stream_chat_completion(openai_messages, model, liveview_pid)
         end) do
      {:ok, task_pid} ->
        TaskRegistry.register_task(user_id, task_pid)
        Process.monitor(task_pid)

        {:noreply,
         socket
         |> stream_insert(:messages, user_message, at: -1)
         |> assign(:has_messages, true)
         |> assign(:streaming_chunks, [])
         |> assign(:streaming_task_pid, task_pid)
         |> assign(:is_streaming, true)
         |> assign(:last_user_message, user_message.content)
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}

      {:error, reason} ->
        Logger.error("Failed to start streaming task: #{inspect(reason)}")

        {:noreply,
         socket
         |> stream_insert(:messages, user_message, at: -1)
         |> put_flash(:error, "Failed to start AI response. Please try again.")
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}
    end
  end

  defp start_agent_loop(socket, user_message, openai_messages, model, user_id) do
    liveview_pid = self()

    on_tool_call = fn tool_call -> send(liveview_pid, {:tool_call_start, tool_call}) end
    on_tool_result = fn result -> send(liveview_pid, {:tool_call_complete, result}) end

    case Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
           result =
             AgentLoop.run(openai_messages,
               user_id: user_id,
               model: model,
               on_tool_call: on_tool_call,
               on_tool_result: on_tool_result
             )

           send(liveview_pid, {:agent_complete, result})
         end) do
      {:ok, task_pid} ->
        TaskRegistry.register_task(user_id, task_pid)
        Process.monitor(task_pid)

        {:noreply,
         socket
         |> stream_insert(:messages, user_message, at: -1)
         |> assign(:has_messages, true)
         |> assign(:streaming_task_pid, task_pid)
         |> assign(:is_streaming, true)
         |> assign(:agent_mode, true)
         |> assign(:pending_tool_calls, [])
         |> assign(:tool_results, [])
         |> assign(:last_user_message, user_message.content)
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}

      {:error, reason} ->
        Logger.error("Failed to start agent loop task: #{inspect(reason)}")

        {:noreply,
         socket
         |> stream_insert(:messages, user_message, at: -1)
         |> put_flash(:error, "Failed to start AI response. Please try again.")
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}
    end
  end

  defp reset_streaming_state(socket) do
    socket
    |> assign(:is_streaming, false)
    |> assign(:streaming_chunks, [])
    |> assign(:last_valid_html, nil)
  end

  defp maybe_update_title(socket, content) do
    if socket.assigns.current_conversation.title == "New Conversation" do
      title = Chat.generate_conversation_title(content)

      case Chat.update_conversation(socket.assigns.current_conversation, %{title: title}) do
        {:ok, updated_conversation} ->
          conversations =
            MessageHelpers.update_conversation_in_list(
              socket.assigns.conversations,
              updated_conversation
            )

          socket
          |> assign(:current_conversation, updated_conversation)
          |> assign(:conversations, conversations)

        {:error, _changeset} ->
          socket
      end
    else
      socket
    end
  end

  defp maybe_update_model(socket, model) do
    if socket.assigns.current_conversation.model_name != model do
      case Chat.update_conversation(socket.assigns.current_conversation, %{model_name: model}) do
        {:ok, updated_conv} -> assign(socket, :current_conversation, updated_conv)
        {:error, _changeset} -> socket
      end
    else
      socket
    end
  end
end
