defmodule ChatbotWeb.Live.Chat.StreamingHelpers do
  @moduledoc """
  Shared helper functions for handling AI streaming in chat LiveViews.

  This module provides common functionality for:
  - Loading available AI models
  - Handling streaming chunks from AI responses
  - Managing streaming state and completion
  - Error handling for streaming failures
  - Per-user concurrent task limiting
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Chatbot.Chat
  alias Chatbot.MCP.AgentLoop
  alias Chatbot.MCP.ToolRegistry
  alias Chatbot.Memory.ContextBuilder
  alias Chatbot.Memory.FactExtractor
  alias Chatbot.ModelCache
  alias Chatbot.ProviderRouter
  alias ChatbotWeb.Plugs.RateLimiter

  require Logger

  # Maximum concurrent streaming tasks per user
  @max_concurrent_tasks 3
  @task_registry_table :streaming_tasks

  @doc """
  Ensures the task registry ETS table exists.
  Called lazily when needed.
  """
  @spec ensure_task_registry() :: :ok
  def ensure_task_registry do
    case :ets.whereis(@task_registry_table) do
      :undefined ->
        :ets.new(@task_registry_table, [:set, :public, :named_table])
        :ok

      _ref ->
        :ok
    end
  end

  @doc """
  Checks if the user can start a new streaming task (within concurrent limit).
  """
  @spec can_start_task?(binary()) :: boolean()
  def can_start_task?(user_id) do
    ensure_task_registry()
    count = get_task_count(user_id)
    count < @max_concurrent_tasks
  end

  @doc """
  Registers a new streaming task for a user.
  """
  @spec register_task(binary(), pid()) :: :ok
  def register_task(user_id, task_pid) do
    ensure_task_registry()
    key = {user_id, task_pid}
    :ets.insert(@task_registry_table, {key, System.monotonic_time(:millisecond)})
    :ok
  end

  @doc """
  Unregisters a streaming task when it completes.
  """
  @spec unregister_task(binary(), pid()) :: :ok
  def unregister_task(user_id, task_pid) do
    ensure_task_registry()
    key = {user_id, task_pid}
    :ets.delete(@task_registry_table, key)
    :ok
  end

  @doc """
  Gets the count of active tasks for a user.
  """
  @spec get_task_count(binary()) :: non_neg_integer()
  def get_task_count(user_id) do
    ensure_task_registry()

    # Count all entries where the first element of the key matches the user_id
    counter = fn
      {{uid, _pid}, _time}, acc when uid == user_id -> acc + 1
      _entry, acc -> acc
    end

    :ets.foldl(counter, 0, @task_registry_table)
  end

  # Helper to unregister a streaming task if one is active
  defp maybe_unregister_streaming_task(socket) do
    user_id = socket.assigns.current_user.id
    task_pid = socket.assigns[:streaming_task_pid]

    if task_pid do
      unregister_task(user_id, task_pid)
    end
  end

  # Helper to update a conversation in the local list without database reload
  defp update_conversation_in_list(conversations, updated_conversation) do
    Enum.map(conversations, fn conv ->
      if conv.id == updated_conversation.id, do: updated_conversation, else: conv
    end)
  end

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

        # Auto-select the first model if none is currently selected
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

  @doc """
  Handles incoming streaming chunks from the AI model.
  Prepends the chunk to the list of streaming chunks (O(1) operation).
  Chunks are stored in reverse order and reversed when rendering.

  Also attempts to parse the accumulated content as markdown and caches
  the last successfully parsed HTML for graceful fallback during streaming.
  """
  @spec handle_chunk(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_chunk(content, socket) do
    chunks = [content | socket.assigns[:streaming_chunks] || []]
    full_content = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    # Try to parse markdown and cache if successful
    # Content is sanitized with HtmlSanitizeEx before rendering as raw HTML
    updated_socket =
      socket
      |> assign(:streaming_chunks, chunks)
      |> maybe_cache_valid_html(full_content)

    {:noreply, updated_socket}
  end

  # Attempts to parse markdown and cache the HTML if successful
  # sobelow_skip ["XSS.Raw"]
  defp maybe_cache_valid_html(socket, content) do
    case Earmark.as_html(content, code_class_prefix: "language-", smartypants: false) do
      {:ok, html_string, _warnings} ->
        html = html_string |> HtmlSanitizeEx.markdown_html() |> Phoenix.HTML.raw()
        assign(socket, :last_valid_html, html)

      {:error, _html, _errors} ->
        # Keep previous last_valid_html
        socket
    end
  end

  @doc """
  Handles completion of streaming response.
  Saves the complete message to the database and updates the UI.
  Uses stream_insert for efficient updates with LiveView streams.
  """
  @spec handle_done(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_done(socket) do
    maybe_unregister_streaming_task(socket)

    conversation_id = socket.assigns.current_conversation.id
    chunks = socket.assigns[:streaming_chunks] || []
    # Chunks are stored in reverse order, so reverse before combining
    complete_message = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    if complete_message != "" do
      # Save assistant message
      # credo:disable-for-lines:20 Credo.Check.Design.DuplicatedCode
      case Chat.create_message(%{
             conversation_id: conversation_id,
             role: "assistant",
             content: complete_message
           }) do
        {:ok, message} ->
          # Update conversation's updated_at locally instead of reloading from DB
          current_conv = socket.assigns.current_conversation
          updated_conv = %{current_conv | updated_at: DateTime.utc_now()}
          conversations = update_conversation_in_list(socket.assigns.conversations, updated_conv)

          # Trigger async fact extraction (fire and forget)
          maybe_extract_facts(socket, complete_message, message.id)

          {:noreply,
           socket
           |> stream_insert(:messages, message, at: -1)
           |> assign(:current_conversation, updated_conv)
           |> assign(:conversations, conversations)
           |> assign(:is_streaming, false)
           |> assign(:streaming_chunks, [])
           |> assign(:last_valid_html, nil)
           |> assign(:last_user_message, nil)
           |> assign(:form, to_form(%{"content" => ""}, as: :message))}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to save assistant message")
           |> assign(:is_streaming, false)
           |> assign(:streaming_chunks, [])
           |> assign(:last_valid_html, nil)}
      end
    else
      {:noreply,
       socket
       |> assign(:is_streaming, false)
       |> assign(:streaming_chunks, [])
       |> assign(:last_valid_html, nil)}
    end
  end

  @doc """
  Handles errors during streaming.
  Displays error message to the user and resets streaming state.
  """
  @spec handle_streaming_error(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_streaming_error(error_msg, socket) do
    maybe_unregister_streaming_task(socket)

    {:noreply,
     socket
     |> put_flash(:error, "Error: #{error_msg}")
     |> assign(:is_streaming, false)
     |> assign(:streaming_chunks, [])
     |> assign(:last_valid_html, nil)}
  end

  @doc """
  Sends a user message and starts streaming AI response.
  Includes rate limiting and error handling.
  """
  @spec send_message_with_streaming(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def send_message_with_streaming(content, socket) do
    if String.trim(content) == "" do
      {:noreply, socket}
    else
      user_id = socket.assigns.current_user.id

      # Check concurrent task limit first
      if can_start_task?(user_id) do
        # Check rate limit before processing
        case RateLimiter.check_message_rate_limit(user_id) do
          :ok ->
            process_message(content, socket)

          {:error, message} ->
            {:noreply, put_flash(socket, :error, message)}
        end
      else
        {:noreply,
         put_flash(
           socket,
           :error,
           "Too many active requests. Please wait for current responses to complete."
         )}
      end
    end
  end

  defp process_message(content, socket) do
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id

    # Save user message
    case Chat.create_message(%{
           conversation_id: conversation_id,
           role: "user",
           content: content
         }) do
      {:ok, user_message} ->
        # Update conversation title if it's the first message
        socket = maybe_update_title(socket, content, user_id)

        model = socket.assigns.selected_model || "default"

        # Build context with memory integration
        {:ok, openai_messages} =
          ContextBuilder.build_context(conversation_id, user_id, current_query: content)

        # Update conversation model if changed
        socket = maybe_update_model(socket, model)

        # Check if user has tools enabled - use agent loop if so, otherwise stream
        if ToolRegistry.user_has_tools?(user_id) do
          process_with_agent_loop(socket, user_message, openai_messages, model, user_id)
        else
          process_with_streaming(socket, user_message, openai_messages, model, user_id)
        end

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save message")}
    end
  end

  # Process message using streaming (no tools)
  defp process_with_streaming(socket, user_message, openai_messages, model, user_id) do
    liveview_pid = self()

    case Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
           ProviderRouter.stream_chat_completion(openai_messages, model, liveview_pid)
         end) do
      {:ok, task_pid} ->
        register_task(user_id, task_pid)
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

  # Process message using agent loop (with tools)
  defp process_with_agent_loop(socket, user_message, openai_messages, model, user_id) do
    liveview_pid = self()

    # Define callbacks to notify LiveView of tool progress
    on_tool_call = fn tool_call ->
      send(liveview_pid, {:tool_call_start, tool_call})
    end

    on_tool_result = fn result ->
      send(liveview_pid, {:tool_call_complete, result})
    end

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
        register_task(user_id, task_pid)
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

  defp maybe_update_title(socket, content, _user_id) do
    if socket.assigns.current_conversation.title == "New Conversation" do
      title = Chat.generate_conversation_title(content)

      case Chat.update_conversation(socket.assigns.current_conversation, %{title: title}) do
        {:ok, updated_conversation} ->
          # Update locally instead of reloading from DB
          conversations =
            update_conversation_in_list(socket.assigns.conversations, updated_conversation)

          socket
          |> assign(:current_conversation, updated_conversation)
          |> assign(:conversations, conversations)

        {:error, _changeset} ->
          # Title update failed, but we can continue without it
          socket
      end
    else
      socket
    end
  end

  defp maybe_update_model(socket, model) do
    if socket.assigns.current_conversation.model_name != model do
      case Chat.update_conversation(socket.assigns.current_conversation, %{model_name: model}) do
        {:ok, updated_conv} ->
          assign(socket, :current_conversation, updated_conv)

        {:error, _changeset} ->
          # Model update failed, but we can continue
          socket
      end
    else
      socket
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

  Options:
    - `:redirect_to` - Path to navigate to after creation (optional)
    - `:reset_streaming` - Whether to reset streaming state (default: false)
  """
  @spec handle_new_conversation(Phoenix.LiveView.Socket.t(), keyword()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_new_conversation(socket, opts \\ []) do
    user_id = socket.assigns.current_user.id

    case Chat.create_conversation(%{
           user_id: user_id,
           title: "New Conversation"
         }) do
      {:ok, conversation} ->
        # Prepend new conversation to list instead of reloading from DB
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

            # Keep the current selected_model - don't reset to nil
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
  Returns appropriate response based on the reason.
  """
  @spec handle_task_down(atom() | term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_task_down(:normal, socket) do
    # Task completed normally, unregister is handled in handle_done
    {:noreply, socket}
  end

  def handle_task_down(_reason, socket) do
    maybe_unregister_streaming_task(socket)

    {:noreply,
     socket
     |> put_flash(:error, "Streaming failed unexpectedly. Please try again.")
     |> assign(:is_streaming, false)
     |> assign(:streaming_chunks, [])
     |> assign(:last_valid_html, nil)}
  end

  # Extracts facts from the conversation asynchronously
  defp maybe_extract_facts(socket, complete_message, message_id) do
    user_id = socket.assigns.current_user.id
    user_message_content = socket.assigns[:last_user_message] || ""
    model = socket.assigns.selected_model || "default"

    if user_message_content != "" do
      Task.Supervisor.start_child(Chatbot.TaskSupervisor, fn ->
        FactExtractor.extract_and_store(
          user_id,
          user_message_content,
          complete_message,
          message_id,
          model
        )
      end)
    end
  end

  # ============================================================================
  # Agent Loop Handlers
  # ============================================================================

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

    # Remove from pending
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

  defp handle_agent_success(result, socket) do
    conversation_id = socket.assigns.current_conversation.id
    complete_message = result.content || ""

    # Save assistant message with any tool_calls info
    message_attrs = %{
      conversation_id: conversation_id,
      role: "assistant",
      content: complete_message
    }

    # credo:disable-for-lines:20 Credo.Check.Design.DuplicatedCode
    case Chat.create_message(message_attrs) do
      {:ok, message} ->
        # Update conversation timestamp locally
        current_conv = socket.assigns.current_conversation
        updated_conv = %{current_conv | updated_at: DateTime.utc_now()}
        conversations = update_conversation_in_list(socket.assigns.conversations, updated_conv)

        # Trigger async fact extraction
        maybe_extract_facts(socket, complete_message, message.id)

        {:noreply,
         socket
         |> stream_insert(:messages, message, at: -1)
         |> assign(:current_conversation, updated_conv)
         |> assign(:conversations, conversations)
         |> assign(:is_streaming, false)
         |> assign(:agent_mode, false)
         |> assign(:pending_tool_calls, [])
         |> assign(:tool_results, [])
         |> assign(:last_user_message, nil)
         |> assign(:form, to_form(%{"content" => ""}, as: :message))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save assistant message")
         |> assign(:is_streaming, false)
         |> assign(:agent_mode, false)
         |> assign(:pending_tool_calls, [])
         |> assign(:tool_results, [])}
    end
  end

  defp handle_agent_error(result, socket) do
    error_msg = result.error || "Agent loop failed"

    {:noreply,
     socket
     |> put_flash(:error, "Error: #{error_msg}")
     |> assign(:is_streaming, false)
     |> assign(:agent_mode, false)
     |> assign(:pending_tool_calls, [])
     |> assign(:tool_results, [])}
  end
end
