defmodule ChatbotWeb.ChatLive.Index do
  @moduledoc """
  Main chat interface LiveView.

  Displays a list of conversations and allows creation of new conversations
  with streaming AI responses from LM Studio.
  """
  use ChatbotWeb, :live_view

  alias Chatbot.Chat
  alias ChatbotWeb.Live.Chat.StreamingHelpers

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id
    conversations = Chat.list_conversations(user_id)

    # Use the most recent conversation or create a new one if none exist
    conversation =
      case conversations do
        [most_recent | _] ->
          most_recent

        [] ->
          {:ok, new_conversation} =
            Chat.create_conversation(%{
              user_id: user_id,
              title: "New Conversation"
            })

          new_conversation
      end

    # Load messages for the conversation
    messages =
      if conversation.id do
        conversation = Chat.get_conversation_with_messages!(conversation.id, user_id)
        conversation.messages
      else
        []
      end

    socket =
      socket
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, conversation)
      |> assign(:messages, messages)
      |> assign(:streaming_chunks, [])
      |> assign(:is_streaming, false)
      |> assign(:available_models, [])
      |> assign(:selected_model, conversation.model_name)
      |> assign(:models_loading, true)
      |> assign(:streaming_task_pid, nil)
      |> assign(:sidebar_open, false)
      |> assign(:form, to_form(%{"content" => ""}, as: :message))

    # Load available models asynchronously only on connected mount
    if connected?(socket) do
      send(self(), :load_models)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_models, socket) do
    socket = assign(socket, :models_loading, false)
    StreamingHelpers.handle_load_models(socket)
  end

  @impl true
  def handle_info({:chunk, content}, socket) do
    StreamingHelpers.handle_chunk(content, socket)
  end

  @impl true
  def handle_info({:done, _}, socket) do
    conversation_id = socket.assigns.current_conversation.id
    user_id = socket.assigns.current_user.id

    # Update conversations list
    socket = assign(socket, :conversations, Chat.list_conversations(user_id))

    StreamingHelpers.handle_done(conversation_id, user_id, socket)
  end

  @impl true
  def handle_info({:error, error_msg}, socket) do
    StreamingHelpers.handle_streaming_error(error_msg, socket)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    StreamingHelpers.handle_task_down(reason, socket)
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    StreamingHelpers.send_message_with_streaming(content, socket)
  end

  @impl true
  def handle_event("select_model", %{"model" => model_id}, socket) do
    StreamingHelpers.handle_select_model(model_id, socket)
  end

  @impl true
  def handle_event("new_conversation", _, socket) do
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
     |> assign(:streaming_chunks, [])
     |> assign(:conversations, Chat.list_conversations(user_id))
     |> assign(:selected_model, conversation.model_name)}
  end

  @impl true
  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200 relative">
      <!-- Mobile Overlay -->
      <%= if @sidebar_open do %>
        <div
          class="fixed inset-0 bg-black bg-opacity-50 z-40 md:hidden"
          phx-click="toggle_sidebar"
          aria-label="Close sidebar"
        >
        </div>
      <% end %>
      
    <!-- Sidebar -->
      <aside
        aria-label="Conversations"
        class={[
          "w-64 bg-base-100 border-r border-base-300 flex flex-col z-50",
          "fixed md:relative inset-y-0 left-0",
          "transform transition-transform duration-200 ease-in-out",
          (@sidebar_open && "translate-x-0") || "-translate-x-full md:translate-x-0"
        ]}
      >
        <div class="p-4 border-b border-base-300 flex items-center justify-between">
          <.button phx-click="new_conversation" class="flex-1">
            New Chat
          </.button>
          <button
            phx-click="toggle_sidebar"
            class="ml-2 btn btn-ghost btn-sm md:hidden"
            aria-label="Close sidebar"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-5 h-5"
              aria-hidden="true"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= for conversation <- @conversations do %>
            <.link
              navigate={~p"/chat/#{conversation.id}"}
              phx-click="toggle_sidebar"
              class={[
                "block p-3 hover:bg-base-200 border-b border-base-300",
                conversation.id == @current_conversation.id && "bg-base-200"
              ]}
            >
              <div class="font-medium truncate">{conversation.title || "New Conversation"}</div>
              <div class="text-xs text-gray-500">
                {Calendar.strftime(conversation.updated_at, "%b %d, %Y")}
              </div>
            </.link>
          <% end %>
        </div>

        <div class="p-4 border-t border-base-300">
          <div class="text-sm text-gray-600">{@current_user.email}</div>
          <.link href={~p"/logout"} method="delete" class="text-sm text-blue-600 hover:underline">
            Logout
          </.link>
        </div>
      </aside>
      
    <!-- Main Chat Area -->
      <main id="main-content" class="flex-1 flex flex-col w-full md:w-auto">
        <!-- Header with hamburger menu and model selection -->
        <div class="bg-base-100 border-b border-base-300 p-4 flex items-center justify-between gap-2">
          <div class="flex items-center gap-2 flex-1 min-w-0">
            <button
              phx-click="toggle_sidebar"
              class="btn btn-ghost btn-sm md:hidden flex-shrink-0"
              aria-label="Open sidebar"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-5 h-5"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
                />
              </svg>
            </button>
            <h2 class="text-lg md:text-xl font-bold truncate">
              {@current_conversation.title || "New Conversation"}
            </h2>
          </div>

          <div class="flex items-center gap-2 flex-shrink-0">
            <label for="model-select" class="text-xs md:text-sm hidden sm:inline">Model:</label>
            <%= if @models_loading do %>
              <span class="loading loading-spinner loading-sm" aria-label="Loading models"></span>
            <% else %>
              <select
                id="model-select"
                phx-change="select_model"
                name="model"
                class="select select-xs md:select-sm select-bordered"
                disabled={@is_streaming}
                aria-label="Select AI model"
              >
                <%= for model <- @available_models do %>
                  <option value={model} selected={model == @selected_model}>
                    {model}
                  </option>
                <% end %>
              </select>
            <% end %>
          </div>
        </div>
        
    <!-- Messages -->
        <div
          class="flex-1 overflow-y-auto p-4 space-y-4"
          id="messages-container"
          role="log"
          aria-label="Chat messages"
          aria-live="polite"
        >
          <%= for message <- @messages do %>
            <div class={["chat", (message.role == "user" && "chat-end") || "chat-start"]}>
              <div class="chat-bubble">
                <div class="whitespace-pre-wrap">{message.content}</div>
              </div>
            </div>
          <% end %>

          <%= if @is_streaming and @streaming_chunks != [] do %>
            <div class="chat chat-start">
              <div class="chat-bubble">
                <div class="whitespace-pre-wrap">{IO.iodata_to_binary(@streaming_chunks)}</div>
                <span class="loading loading-dots loading-sm"></span>
              </div>
            </div>
          <% end %>

          <%= if @is_streaming and @streaming_chunks == [] do %>
            <div class="chat chat-start">
              <div class="chat-bubble">
                <span class="loading loading-dots loading-md"></span>
              </div>
            </div>
          <% end %>
        </div>
        
    <!-- Input Form -->
        <div class="bg-base-100 border-t border-base-300 p-4">
          <.form for={@form} phx-submit="send_message" class="flex gap-2" aria-label="Send message">
            <.input
              field={@form[:content]}
              type="textarea"
              placeholder="Type your message..."
              class="flex-1"
              disabled={@is_streaming}
              aria-label="Message input"
            />
            <.button type="submit" disabled={@is_streaming} aria-label="Send message">
              <%= if @is_streaming do %>
                <span class="loading loading-spinner" aria-label="Sending"></span>
              <% else %>
                Send
              <% end %>
            </.button>
          </.form>
        </div>
      </main>
    </div>
    """
  end
end
