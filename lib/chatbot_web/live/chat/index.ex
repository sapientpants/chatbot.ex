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
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200">
      <!-- Sidebar -->
      <div class="w-64 bg-base-100 border-r border-base-300 flex flex-col">
        <div class="p-4 border-b border-base-300">
          <.button phx-click="new_conversation" class="w-full">
            New Chat
          </.button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= for conversation <- @conversations do %>
            <.link
              navigate={~p"/chat/#{conversation.id}"}
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
      </div>
      
    <!-- Main Chat Area -->
      <div class="flex-1 flex flex-col">
        <!-- Header with model selection -->
        <div class="bg-base-100 border-b border-base-300 p-4 flex items-center justify-between">
          <h2 class="text-xl font-bold">{@current_conversation.title || "New Conversation"}</h2>

          <div class="flex items-center gap-2">
            <label class="text-sm">Model:</label>
            <%= if @models_loading do %>
              <span class="loading loading-spinner loading-sm"></span>
            <% else %>
              <select
                phx-change="select_model"
                name="model"
                class="select select-sm select-bordered"
                disabled={@is_streaming}
              >
                <%= for model <- @available_models do %>
                  <option value={model["id"]} selected={model["id"] == @selected_model}>
                    {model["id"]}
                  </option>
                <% end %>
              </select>
            <% end %>
          </div>
        </div>
        
    <!-- Messages -->
        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="messages-container">
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
          <.form for={@form} phx-submit="send_message" class="flex gap-2">
            <.input
              field={@form[:content]}
              type="textarea"
              placeholder="Type your message..."
              class="flex-1"
              disabled={@is_streaming}
            />
            <.button type="submit" disabled={@is_streaming}>
              <%= if @is_streaming do %>
                <span class="loading loading-spinner"></span>
              <% else %>
                Send
              <% end %>
            </.button>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
