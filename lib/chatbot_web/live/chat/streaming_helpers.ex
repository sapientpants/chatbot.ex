defmodule ChatbotWeb.Live.Chat.StreamingHelpers do
  @moduledoc """
  Shared helper functions for handling AI streaming in chat LiveViews.

  This module provides common functionality for:
  - Loading available AI models
  - Handling streaming chunks from AI responses
  - Managing streaming state and completion
  - Error handling for streaming failures

  For task registry management, see `TaskRegistry`.
  For agent loop handling, see `AgentLoopHandlers`.
  For message processing, see `MessageProcessor`.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Chatbot.Chat
  alias Chatbot.ModelCache
  alias ChatbotWeb.Live.Chat.MessageProcessor
  alias ChatbotWeb.Live.Chat.TaskRegistry
  alias ChatbotWeb.Live.Chat.UploadHelpers
  alias ChatbotWeb.Plugs.RateLimiter

  require Logger

  # Re-export TaskRegistry functions for backwards compatibility
  defdelegate can_start_task?(user_id), to: TaskRegistry
  defdelegate register_task(user_id, task_pid), to: TaskRegistry
  defdelegate unregister_task(user_id, task_pid), to: TaskRegistry
  defdelegate get_task_count(user_id), to: TaskRegistry
  defdelegate ensure_task_registry(), to: TaskRegistry, as: :ensure_registry

  @doc """
  Handles loading available models from LM Studio.
  Uses the ModelCache to avoid repeated API calls.
  """
  @spec handle_load_models(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_load_models(socket) do
    case ModelCache.get_models() do
      {:ok, models} ->
        model_list = Enum.map(models, & &1["id"])

        socket =
          if is_nil(socket.assigns.selected_model) and model_list != [] do
            assign(socket, :selected_model, List.first(model_list))
          else
            socket
          end

        {:noreply, assign(socket, :available_models, model_list)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to load available models")
         |> assign(:available_models, [])}
    end
  end

  @doc "Handles incoming streaming chunks from the AI model."
  @spec handle_chunk(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_chunk(content, socket) do
    chunks = [content | socket.assigns[:streaming_chunks] || []]
    full_content = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    updated_socket =
      socket
      |> assign(:streaming_chunks, chunks)
      |> maybe_cache_valid_html(full_content)

    {:noreply, updated_socket}
  end

  @doc "Handles completion of streaming response."
  @spec handle_done(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_done(socket) do
    maybe_unregister_streaming_task(socket)

    conversation_id = socket.assigns.current_conversation.id
    chunks = socket.assigns[:streaming_chunks] || []
    complete_message = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    if complete_message != "" do
      MessageProcessor.save_assistant_message(socket, conversation_id, complete_message)
    else
      {:noreply, reset_streaming_state(socket)}
    end
  end

  @doc """
  Handles errors during streaming.
  """
  @spec handle_streaming_error(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_streaming_error(error_msg, socket) do
    maybe_unregister_streaming_task(socket)

    {:noreply,
     socket
     |> put_flash(:error, "Error: #{error_msg}")
     |> reset_streaming_state()}
  end

  @doc """
  Sends a user message and starts streaming AI response.

  If there are pending file uploads, they are automatically uploaded before
  processing the message, ensuring attached documents are available for RAG.
  """
  @spec send_message_with_streaming(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def send_message_with_streaming(content, socket) do
    if String.trim(content) == "" do
      {:noreply, socket}
    else
      user_id = socket.assigns.current_user.id

      case RateLimiter.check_message_rate_limit(user_id) do
        :ok ->
          # Auto-upload pending files before processing message
          socket = auto_upload_pending_files(socket)
          # MessageProcessor handles atomic task registration
          MessageProcessor.process(content, socket)

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    end
  end

  @doc """
  Handles model selection change.
  """
  @spec handle_select_model(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_select_model(model_id, socket) do
    {:noreply, assign(socket, :selected_model, model_id)}
  end

  @doc """
  Creates a new conversation.
  """
  @spec handle_new_conversation(Phoenix.LiveView.Socket.t(), keyword()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_new_conversation(socket, opts \\ []) do
    user_id = socket.assigns.current_user.id

    case Chat.create_conversation(%{user_id: user_id, title: "New Conversation"}) do
      {:ok, conversation} ->
        conversations = [conversation | socket.assigns.conversations]

        socket =
          socket
          |> assign(:current_conversation, conversation)
          |> stream(:messages, [], reset: true)
          |> assign(:conversations, conversations)

        socket =
          if opts[:reset_streaming] do
            socket
            |> assign(:has_messages, false)
            |> assign(:streaming_chunks, [])
            |> assign(:last_valid_html, nil)
          else
            socket
          end

        socket =
          if redirect_path = opts[:redirect_to] do
            push_navigate(socket, to: redirect_path)
          else
            socket
          end

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create conversation")}
    end
  end

  @doc """
  Handles task crash/completion monitoring.
  """
  @spec handle_task_down(atom() | term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_task_down(:normal, socket), do: {:noreply, socket}

  def handle_task_down(_reason, socket) do
    maybe_unregister_streaming_task(socket)

    {:noreply,
     socket
     |> put_flash(:error, "Streaming failed unexpectedly. Please try again.")
     |> reset_streaming_state()}
  end

  # Private helpers

  defp reset_streaming_state(socket) do
    socket
    |> assign(:is_streaming, false)
    |> assign(:streaming_chunks, [])
    |> assign(:last_valid_html, nil)
  end

  # sobelow_skip ["XSS.Raw"]
  defp maybe_cache_valid_html(socket, content) do
    case Earmark.as_html(content, code_class_prefix: "language-", smartypants: false) do
      {:ok, html_string, _warnings} ->
        html = html_string |> HtmlSanitizeEx.markdown_html() |> Phoenix.HTML.raw()
        assign(socket, :last_valid_html, html)

      {:error, _html, _errors} ->
        socket
    end
  end

  defp maybe_unregister_streaming_task(socket) do
    user_id = socket.assigns.current_user.id
    task_pid = socket.assigns[:streaming_task_pid]
    if task_pid, do: unregister_task(user_id, task_pid)
  end

  defp auto_upload_pending_files(socket) do
    uploads = socket.assigns[:uploads]
    entries = uploads && uploads[:markdown_files] && uploads.markdown_files.entries

    if entries && entries != [] do
      case UploadHelpers.handle_upload(socket) do
        {:ok, updated_socket} ->
          updated_socket

        {:error, updated_socket, error_msg} ->
          Logger.warning("Auto-upload failed: #{error_msg}")
          put_flash(updated_socket, :error, error_msg)
      end
    else
      socket
    end
  end
end
