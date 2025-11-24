defmodule ChatbotWeb.Live.Chat.StreamingHelpers do
  @moduledoc """
  Shared helper functions for handling AI streaming in chat LiveViews.

  This module provides common functionality for:
  - Loading available AI models
  - Handling streaming chunks from AI responses
  - Managing streaming state and completion
  - Error handling for streaming failures
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Chatbot.{Chat, LMStudio}
  alias ChatbotWeb.Plugs.RateLimiter

  @doc """
  Handles loading available models from LM Studio.
  Sends the result back to the calling LiveView process.
  """
  def handle_load_models(socket) do
    case LMStudio.list_models() do
      {:ok, models} ->
        model_list = Enum.map(models, & &1["id"])
        {:noreply, assign(socket, :available_models, model_list)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to load available models")
         |> assign(:available_models, [])}
    end
  end

  @doc """
  Handles incoming streaming chunks from the AI model.
  Appends the chunk to the list of streaming chunks.
  """
  def handle_chunk(content, socket) do
    chunks = socket.assigns[:streaming_chunks] || []
    {:noreply, assign(socket, :streaming_chunks, chunks ++ [content])}
  end

  @doc """
  Handles completion of streaming response.
  Saves the complete message to the database and updates the UI.
  """
  def handle_done(conversation_id, user_id, socket) do
    chunks = socket.assigns[:streaming_chunks] || []
    complete_message = IO.iodata_to_binary(chunks)

    if complete_message != "" do
      # Save assistant message
      {:ok, _message} =
        Chat.create_message(%{
          conversation_id: conversation_id,
          role: "assistant",
          content: complete_message
        })

      # Append the new message to the existing list instead of reloading all
      new_message = %Chatbot.Chat.Message{
        conversation_id: conversation_id,
        role: "assistant",
        content: complete_message,
        inserted_at: DateTime.utc_now()
      }

      messages = socket.assigns.messages ++ [new_message]
      conversations = Chat.list_conversations(user_id)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:conversations, conversations)
       |> assign(:is_streaming, false)
       |> assign(:streaming_chunks, [])
       |> assign(:form, to_form(%{"content" => ""}, as: :message))}
    else
      {:noreply,
       socket
       |> assign(:is_streaming, false)
       |> assign(:streaming_chunks, [])}
    end
  end

  @doc """
  Handles errors during streaming.
  Displays error message to the user and resets streaming state.
  """
  def handle_streaming_error(error_msg, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Error: #{error_msg}")
     |> assign(:is_streaming, false)
     |> assign(:streaming_chunks, [])}
  end

  @doc """
  Sends a user message and starts streaming AI response.
  Includes rate limiting and error handling.
  """
  def send_message_with_streaming(content, socket) do
    if String.trim(content) == "" do
      {:noreply, socket}
    else
      user_id = socket.assigns.current_user.id

      # Check rate limit before processing
      case RateLimiter.check_message_rate_limit(user_id) do
        :ok ->
          process_message(content, socket)

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    end
  end

  defp process_message(content, socket) do
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id

    # Save user message
    {:ok, user_message} =
      Chat.create_message(%{
        conversation_id: conversation_id,
        role: "user",
        content: content
      })

    # Update conversation title if it's the first message
    socket =
      if socket.assigns.current_conversation.title == "New Conversation" do
        title = Chat.generate_conversation_title(content)

        {:ok, updated_conversation} =
          Chat.update_conversation(socket.assigns.current_conversation, %{title: title})

        socket
        |> assign(:current_conversation, updated_conversation)
        |> assign(:conversations, Chat.list_conversations(user_id))
      else
        socket
      end

    # Append user message to existing messages instead of reloading
    messages = socket.assigns.messages ++ [user_message]

    # Build OpenAI format messages
    openai_messages = Chat.build_openai_messages(messages)

    # Start streaming response from LM Studio
    model = socket.assigns.selected_model || "default"

    # Update conversation model if changed
    socket =
      if socket.assigns.current_conversation.model_name != model do
        {:ok, updated_conv} =
          Chat.update_conversation(socket.assigns.current_conversation, %{model_name: model})

        assign(socket, :current_conversation, updated_conv)
      else
        socket
      end

    # Capture LiveView PID before starting Task and monitor it
    liveview_pid = self()

    {:ok, task_pid} =
      Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
        LMStudio.stream_chat_completion(openai_messages, model, liveview_pid)
      end)

    # Monitor the task to handle crashes
    Process.monitor(task_pid)

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:streaming_chunks, [])
     |> assign(:streaming_task_pid, task_pid)
     |> assign(:is_streaming, true)
     |> assign(:form, to_form(%{"content" => ""}, as: :message))}
  end

  @doc """
  Handles model selection change.
  """
  def handle_select_model(model_id, socket) do
    {:noreply, assign(socket, :selected_model, model_id)}
  end

  @doc """
  Creates a new conversation and navigates to the chat index.
  """
  def handle_new_conversation(socket, redirect_path) do
    user_id = socket.assigns.current_user.id

    {:ok, conversation} =
      Chat.create_conversation(%{
        user_id: user_id,
        title: "New Conversation"
      })

    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:messages, [])
     |> assign(:conversations, Chat.list_conversations(user_id))
     |> push_navigate(to: redirect_path)}
  end

  @doc """
  Handles task crash/completion monitoring.
  Returns appropriate response based on the reason.
  """
  def handle_task_down(:normal, socket) do
    # Task completed normally, nothing to do
    {:noreply, socket}
  end

  def handle_task_down(reason, socket) do
    # Task crashed, show error
    {:noreply,
     socket
     |> put_flash(:error, "Streaming failed: #{inspect(reason)}")
     |> assign(:is_streaming, false)
     |> assign(:streaming_chunks, [])}
  end
end
